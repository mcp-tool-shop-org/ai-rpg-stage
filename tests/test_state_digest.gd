## test_state_digest.gd — canonical state digest v2 parity, automatic post-submit
## verification, bounded snapshot resync (cap 3), and handshake version enforcement.
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const StateDigest := preload("res://client/state_digest.gd")
const Framing := preload("res://client/framing.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")
const Diorama := preload("res://stage/diorama.gd")
const Session := preload("res://stage/session.gd")
const Playable := preload("res://stage/playable.gd")

const HOST_PACK := "chapel-threshold"
const SEED := 71


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "SceneTree available", "async wire tests require process frames")
		return

	_test_shared_vectors_and_patches(t)
	await _test_handshake_version_gate(t, tree)
	await _test_live_verify_resync_and_cap(t, tree)
	await _test_pre_baseline_syncing_gate(t, tree)
	await _test_a2_edge_paths_and_tick_dedup(t, tree)


func _test_shared_vectors_and_patches(t: RefCounted) -> void:
	var vectors_path := Harness.find_engine_dir() + "/fixtures/state_digest_vectors.jsonl"
	t.is_true(FileAccess.file_exists(vectors_path),
		"engine shared vectors file exists (%s)" % vectors_path)
	if FileAccess.file_exists(vectors_path):
		var raw := FileAccess.get_file_as_string(vectors_path)
		var lines := raw.split("\n", false)
		var vector_checked := 0
		for line: String in lines:
			var s := line.strip_edges()
			if s.is_empty():
				continue
			var rec_v: Variant = JSON.parse_string(s)
			t.check(rec_v is Dictionary, "vector line parses as JSON object")
			if not (rec_v is Dictionary):
				continue
			var rec := rec_v as Dictionary
			var vid := String(rec.get("id", "?"))
			if rec.has("expected_error"):
				var err_code := String(rec["expected_error"])
				var lit := String(rec.get("raw_json_literal", ""))
				if err_code == "NUL_CHARACTER":
					var parsed_lit: Variant = JSON.parse_string(lit)
					t.check(parsed_lit is Dictionary and String((parsed_lit as Dictionary).get("s", "")).unicode_at(1) == 0xFFFD,
						"vector %s: NUL substituted cleanly on parse" % vid)
				elif err_code == "LONE_SURROGATE":
					var jp := JSON.new()
					t.not_equals(jp.parse(lit), OK, "vector %s: lone surrogate refused" % vid)
			else:
				var pre: String = StateDigest.canonical_json(rec.get("input", null))
				var dig: String = StateDigest.canonical_state_hash(rec.get("input", null))
				t.equals(pre, String(rec.get("expected_preimage", "")), "vector %s preimage" % vid)
				t.equals(dig, String(rec.get("expected_hash", "")), "vector %s hash" % vid)
			vector_checked += 1
		t.check(vector_checked >= 23, "checked all shared engine vectors", "got %d" % vector_checked)

	# Error branches on StateDigest.
	var non_ascii := StateDigest.try_canonical_json({"café": 1})
	t.is_false(bool(non_ascii.get("ok", true)), "non-ASCII object key refused")
	t.equals(String(non_ascii.get("code", "")), "NON_ASCII_KEY", "non-ASCII key code matches")

	var non_finite := StateDigest.try_canonical_json(NAN)
	t.is_false(bool(non_finite.get("ok", true)), "NaN refused in canonical JSON")
	t.equals(String(non_finite.get("code", "")), "NON_FINITE_NUMBER", "non-finite error code matches")

	var unsafe_int := StateDigest.try_canonical_json(1e15)
	t.is_false(bool(unsafe_int.get("ok", true)), "scaled integer beyond 2^53 - 1 refused")
	t.equals(String(unsafe_int.get("code", "")), "UNSAFE_SCALED_INTEGER", "unsafe int error code matches")

	var bad_type := StateDigest.try_canonical_state_hash(Vector2(1, 2))
	t.is_false(bool(bad_type.get("ok", true)), "unsupported Variant type refused by hash helper")
	t.equals(String(bad_type.get("code", "")), "UNSUPPORTED_VALUE_TYPE", "unsupported Variant error code matches")

	# Patch application (both engine array paths and RFC 6902 pointer strings, plus __proto__ guard).
	var patched: Variant = StateDigest.apply_patches({}, [
		{"op": "set", "path": ["zones", "quay", "items", 0], "value": {"id": "lantern"}},
		{"op": "add", "path": "/zones/quay/items/-", "value": {"id": "rope"}},
		{"op": "replace", "path": "/zones/quay/items/0", "value": {"id": "torch"}},
		{"op": "set", "path": ["__proto__", "polluted"], "value": true},
		{"op": "remove", "path": "/zones/quay/items/1"},
	])
	t.check(patched is Dictionary and not (patched as Dictionary).has("__proto__"),
		"__proto__ segment is ignored in apply_patches")
	var items: Array = ((patched as Dictionary)["zones"]["quay"]["items"] as Array)
	t.equals(items.size(), 1, "RFC 6902 add/replace/remove + array paths applied")
	t.equals(String((items[0] as Dictionary).get("id", "")), "torch", "patched item holds updated value")

	# First differing UTF-8 byte offset.
	t.equals(StateDigest.first_diff_offset("{\"a\":1}", "{\"a\":2}"), 5, "first_diff_offset locates exact differing byte")
	t.equals(StateDigest.first_diff_offset("{\"a\":1}", "{\"a\":1}x"), 7, "first_diff_offset detects length prefix difference")
	t.equals(StateDigest.first_diff_offset("{\"a\":1}", "{\"a\":1}"), -1, "identical pre-images return -1")


func _test_handshake_version_gate(t: RefCounted, tree: SceneTree) -> void:
	# Whole float 2.0 with capabilities.canonicalHashes is accepted cleanly.
	var probe_client := NetworkClient.new()
	var accept_float := String(probe_client.call("_validate_handshake_digest_version", {
		"serverName": "mock",
		"engineVersion": "0.0.0",
		"digest_spec_version": 2.0,
		"capabilities": {"hashes": true, "canonicalHashes": true},
	}))
	t.equals(accept_float, "", "whole-float digest_spec_version 2.0 with canonicalHashes is accepted")
	probe_client.free()

	for case_spec: Dictionary in [
		{"label": "unsupported v1", "result": {"serverName": "mock", "engineVersion": "0.0.0", "digest_spec_version": 1, "capabilities": {"hashes": true, "canonicalHashes": true}}, "expect": "unsupported digest_spec_version"},
		{"label": "fractional float version", "result": {"serverName": "mock", "engineVersion": "0.0.0", "digest_spec_version": 2.5, "capabilities": {"hashes": true, "canonicalHashes": true}}, "expect": "unsupported digest_spec_version"},
		{"label": "missing version", "result": {"serverName": "mock", "engineVersion": "0.0.0", "capabilities": {"hashes": true, "canonicalHashes": true}}, "expect": "unsupported digest_spec_version"},
		{"label": "refused canonicalHashes", "result": {"serverName": "mock", "engineVersion": "0.0.0", "digest_spec_version": 2, "capabilities": {"hashes": true, "canonicalHashes": false}}, "expect": "server refused capabilities.canonicalHashes"},
	]:
		var server := TCPServer.new()
		var listen_err := server.listen(0, "127.0.0.1")
		t.equals(listen_err, OK, "mock server listens for %s" % case_spec["label"])
		if listen_err != OK:
			continue
		var port := server.get_local_port()

		var d := Diorama.new()
		tree.root.add_child(d)
		await tree.process_frame

		var hud := Playable.new()
		d.add_child(hud)

		var served := false
		var attach_task := func() -> void:
			await hud.call("_attach", "127.0.0.1:%d" % port)
		# Drive client attach coroutine while answering the single initialize request.
		var state := {"done": false}
		var runner := func() -> void:
			await attach_task.call()
			state["done"] = true
		runner.call()

		var peer: StreamPeerTCP = null
		var buf := PackedByteArray()
		for _tick in range(180):
			if server.is_connection_available() and peer == null:
				peer = server.take_connection()
				peer.set_no_delay(true)
			if peer != null:
				peer.poll()
				if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
					var avail := peer.get_available_bytes()
					if avail > 0:
						var got := peer.get_partial_data(avail)
						if int(got[0]) == OK:
							buf.append_array(got[1] as PackedByteArray)
					if not served and buf.size() > 0:
						var framing := Framing.new()
						var msgs: Array = framing.push(buf)
						if msgs.size() > 0 and msgs[0] is Dictionary:
							var req := msgs[0] as Dictionary
							var resp := Framing.encode({
								"jsonrpc": "2.0",
								"id": req.get("id", 1),
								"result": case_spec["result"],
							})
							peer.put_data(resp)
							served = true
			if bool(state["done"]):
				break
			await tree.process_frame

		t.is_true(served, "mock handshake served initialize for %s" % case_spec["label"])
		t.is_true(bool(state["done"]), "playable._attach completed for %s" % case_spec["label"])
		var client_node: Node = hud.get("client")
		t.check(client_node != null, "playable created NetworkClient")
		if client_node != null:
			t.is_false(bool(client_node.call("is_attached")),
				"attach fails on %s" % case_spec["label"])
			t.contains(String(client_node.call("last_attach_error")), String(case_spec["expect"]),
				"last_attach_error names %s" % case_spec["expect"])
		var status_lbl: Label = hud.get("_status")
		var log_rtl: RichTextLabel = hud.get("_log")
		t.contains(status_lbl.text, "load error", "HUD status shows visible load error for %s" % case_spec["label"])
		t.contains(log_rtl.text, "Load error:", "HUD log shows visible load error for %s" % case_spec["label"])

		if peer != null:
			peer.disconnect_from_host()
		server.stop()
		hud.queue_free()
		d.queue_free()
		await tree.process_frame


func _test_live_verify_resync_and_cap(t: RefCounted, tree: SceneTree) -> void:
	var harness: RefCounted = Harness.new()
	var extra: Array[String] = [
		"--content", Harness.salt_road_pack(),
		"--manifest", Harness.salt_road_manifest(),
		"--start", Diorama.PLAYER_START_ZONE,
		"--shock", "dockward:stability:-25@2",
	]
	harness.extra_args = extra
	if not await harness.call("start", HOST_PACK, SEED):
		t.check(false, "sidecar started for digest live test", String(harness.get("failure")))
		return

	var bus := EventBus.new()
	bus.name = "DigestBus"
	tree.root.add_child(bus)

	var client := NetworkClient.new()
	client.name = "DigestClient"
	client.bus = bus
	tree.root.add_child(client)

	var d := Diorama.new()
	d.name = "DigestDiorama"
	tree.root.add_child(d)
	await tree.process_frame
	d.call("build")

	var session := Session.new()
	session.name = "DigestSession"
	tree.root.add_child(session)
	session.call("setup", d, client, bus)

	var handshake: Dictionary = await client.call("attach", Harness.HOST, int(harness.get("port")), "stage/test-digest", "0.1.0")
	t.is_false(handshake.is_empty(), "handshake succeeded on real pinned sidecar")
	t.equals(int(handshake.get("digest_spec_version", 0)), 2, "server reports digest_spec_version 2")
	var caps := handshake.get("capabilities", {}) as Dictionary
	t.is_true(bool(caps.get("canonicalHashes", false)), "handshake granted capabilities.canonicalHashes")

	var snap: Dictionary = await client.call("snapshot")
	t.is_false(bool(snap.get("__error__", false)), "initial snapshot succeeded")
	t.equals(String(client.call("mirror_digest")), String(snap.get("canonicalHash", "")),
		"initial mirror canonical digest matches snapshot canonicalHash")

	# Wait frame so any queued tick settles cleanly.
	await tree.process_frame

	# Clean move first: automatic post-submit digest matches with 0 resyncs.
	await session.call("walk_to", "weighing-floor")
	t.equals(int(client.call("total_resyncs")), 0, "clean play move matches engine canonicalHash with 0 resyncs")

	# 1. Forced mismatch using the production _debug_corrupt_recorded_hash hook BEFORE a play submit
	# (NOT calling verify_position()!) — proves automatic post-submit check + resync + pre-image offset logging.
	var stale_events: Array[String] = []
	bus.staleness_detected.connect(func(detail: String) -> void: stale_events.append(detail))

	client.call("_debug_corrupt_recorded_hash", int(client.call("current_tick")))
	await session.call("walk_to", "long-quay")

	t.equals(stale_events.size(), 1, "play submit automatically detects drift without verify_position()")
	if stale_events.size() > 0:
		t.contains(stale_events[0], "first differing pre-image offset",
			"mismatch report logs the first differing pre-image offset")
	t.equals(int(client.call("total_resyncs")), 1, "exact 1 snapshot resync ran after play submit")
	t.equals(int(client.call("consecutive_resyncs")), 1, "consecutive resync count incremented to 1")
	t.is_false(bool(client.call("is_halted")), "single resync does not halt play")
	t.equals(String(client.call("mirror_digest")), String(client.call("canonical_hash_for_tick", int(client.call("current_tick")))),
		"fresh snapshot mirror canonical digest matches engine digest immediately")

	# Play-path reset: a clean session.walk_to WITHOUT any verify_position() call in between
	# must reset consecutive_resyncs to 0 and clear stale state.
	await session.call("walk_to", "customs-shed")
	t.equals(int(client.call("consecutive_resyncs")), 0, "clean play walk_to resets consecutive resync streak without verify_position()")
	t.is_false(bool(client.call("is_stale")), "clean play walk_to clears stale state")

	# Separated mismatches: 4 additional mismatches each followed by a clean walk_to move
	# (with no verify_position() between them) exceed 3 total resyncs without tripping the consecutive cap.
	var return_zones: Array[String] = ["long-quay", "customs-shed", "long-quay", "customs-shed"]
	for cycle_idx in range(return_zones.size()):
		client.call("_debug_corrupt_recorded_hash", int(client.call("current_tick")))
		await session.call("advance")
		t.is_false(bool(client.call("is_halted")),
			"separated mismatch %d does not halt before clean recovery move" % (cycle_idx + 1))
		await session.call("walk_to", return_zones[cycle_idx])
		t.equals(int(client.call("consecutive_resyncs")), 0,
			"clean walk_to after separated mismatch %d resets consecutive streak to 0" % (cycle_idx + 1))
		t.is_false(bool(client.call("is_stale")),
			"clean walk_to after separated mismatch %d clears stale state" % (cycle_idx + 1))
		t.is_false(bool(client.call("is_halted")),
			"separated mismatch %d stays unhalted across 3+ non-consecutive resyncs" % (cycle_idx + 1))
	t.equals(int(client.call("total_resyncs")), 5, "all 5 non-consecutive mismatches resynced cleanly without halting")

	var verified_now: bool = await client.call("verify_position")
	t.is_true(verified_now, "subsequent verify_position() still agrees after separated resync cycles")
	t.equals(int(client.call("consecutive_resyncs")), 0, "consecutive resync counter remains 0 after verify_position()")

	# 2. Four consecutive forced mismatches (no clean move between them) cap at 3 and halt on the 4th.
	var halted_events: Array[String] = []
	bus.session_halted.connect(func(reason: String) -> void: halted_events.append(reason))
	client.suppress_ci_halt_marker = true

	for attempt in range(1, 5):
		client.call("_debug_corrupt_recorded_hash", int(client.call("current_tick")))
		await session.call("advance")
		if attempt <= 3:
			t.is_false(bool(client.call("is_halted")),
				"consecutive resync %d/3 remains within the consecutive cap" % attempt)
			t.equals(int(client.call("consecutive_resyncs")), attempt,
				"consecutive resync streak tracks %d/3" % attempt)
		else:
			t.is_true(bool(client.call("is_halted")),
				"4th consecutive mismatch exceeds cap of 3 and halts client")

	t.equals(halted_events.size(), 1, "session_halted fired once past cap")
	if halted_events.size() > 0:
		t.contains(halted_events[0], "resync cap exceeded", "halt reason names cap exceeded")
	t.is_true(bool(session.call("is_halted")), "Session marked halted")

	var found_visible_halt := false
	for line: Variant in (session.get("transcript") as Array):
		if String(line).contains("Sync halted:"):
			found_visible_halt = true
	t.is_true(found_visible_halt, "halt error is rendered visibly in session.transcript")

	var found_diag_halt := false
	for dline: Variant in (session.get("diagnostics") as Array):
		if String(dline).contains("[halt]"):
			found_diag_halt = true
	t.is_true(found_diag_halt, "halt error is also recorded in session.diagnostics")

	# Further moves are refused after halt without resyncing.
	var resyncs_at_halt := int(client.call("total_resyncs"))
	var blocked_move: Dictionary = await session.call("walk_to", "long-quay")
	t.is_true(bool(blocked_move.get("__error__", false)), "play move refused once halted")
	t.equals(int(client.call("total_resyncs")), resyncs_at_halt, "no additional resyncs occur after halt")

	client.call("detach")
	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	harness.call("stop")
	await tree.create_timer(0.4).timeout

	# Immediate snapshot digest mismatch also halts at once (using a mock RPC response).
	var snap_srv := TCPServer.new()
	if snap_srv.listen(0, "127.0.0.1") == OK:
		var sport := snap_srv.get_local_port()
		var sbus := EventBus.new()
		var sclient := NetworkClient.new()
		sclient.bus = sbus
		sclient.suppress_ci_halt_marker = true
		tree.root.add_child(sbus)
		tree.root.add_child(sclient)
		var bad_snap_halts: Array[String] = []
		sbus.session_halted.connect(func(r: String) -> void: bad_snap_halts.append(r))
		var sstate := {"done": false}
		var srun := func() -> void:
			await sclient.call("attach", "127.0.0.1", sport, "stage/test-snap-bad")
			await sclient.call("snapshot")
			sstate["done"] = true
		srun.call()
		var speer: StreamPeerTCP = null
		var sbuf := PackedByteArray()
		var sframing := Framing.new()
		for _i in range(180):
			if snap_srv.is_connection_available() and speer == null:
				speer = snap_srv.take_connection()
				speer.set_no_delay(true)
			if speer != null:
				speer.poll()
				if speer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
					var av := speer.get_available_bytes()
					if av > 0:
						var g := speer.get_partial_data(av)
						if int(g[0]) == OK:
							sbuf.append_array(g[1] as PackedByteArray)
							for msg: Variant in sframing.push(sbuf):
								sbuf.clear()
								if msg is Dictionary:
									var m := msg as Dictionary
									var meth := String(m.get("method", ""))
									if meth == "initialize":
										speer.put_data(Framing.encode({"jsonrpc": "2.0", "id": m.get("id", 1), "result": {"serverName": "mock", "engineVersion": "0.0.0", "digest_spec_version": 2, "capabilities": {"hashes": true, "canonicalHashes": true}, "tick": 0}}))
									elif meth == "snapshot":
										speer.put_data(Framing.encode({"jsonrpc": "2.0", "id": m.get("id", 2), "result": {"tick": 0, "hash": "0000", "canonicalHash": "ffffffffffffffffffffffffffffffff", "snapshotSeq": 1, "delta": [{"op": "set", "path": ["tick"], "value": 0}]}}))
			if bool(sstate["done"]):
				break
			await tree.process_frame
		t.is_true(bool(sclient.call("is_halted")), "immediate post-snapshot digest mismatch halts session")
		t.equals(bad_snap_halts.size(), 1, "bad snapshot digest emits session_halted")
		if bad_snap_halts.size() > 0:
			t.contains(bad_snap_halts[0], "snapshot digest mismatch", "halt names snapshot digest mismatch")
		if speer != null:
			speer.disconnect_from_host()
		snap_srv.stop()
		sclient.queue_free()
		sbus.queue_free()
		await tree.process_frame


func _test_pre_baseline_syncing_gate(t: RefCounted, tree: SceneTree) -> void:
	# 1. Calling post-submit mirror verification without a baseline refuses loudly rather than silently skipping.
	var unbaselined_bus := EventBus.new()
	var unbaselined_client := NetworkClient.new()
	unbaselined_client.bus = unbaselined_bus
	tree.root.add_child(unbaselined_bus)
	tree.root.add_child(unbaselined_client)
	var pre_stale: Array[String] = []
	unbaselined_bus.staleness_detected.connect(func(detail: String) -> void: pre_stale.append(detail))
	var verify_no_base: bool = await unbaselined_client.call("_verify_mirror_after_submit", {"tick": 0, "canonicalHash": "abc"})
	t.is_false(verify_no_base, "post-submit verification returns false without baseline")
	t.is_true(pre_stale.size() > 0, "_verify_mirror_after_submit without baseline reports staleness rather than skipping silently")
	t.is_true(bool(unbaselined_client.call("is_stale")), "_verify_mirror_after_submit without baseline marks client stale")
	unbaselined_client.queue_free()
	unbaselined_bus.queue_free()
	await tree.process_frame

	# 2. Playable HUD holds snapshot in flight: shows on-screen 'syncing', refuses key/iso/session/client input,
	#    then accepts and verifies play input once the baseline snapshot lands.
	var srv := TCPServer.new()
	if srv.listen(0, "127.0.0.1") != OK:
		t.check(false, "mock server listening for pre-baseline HUD test", "TCPServer.listen failed")
		return
	var port := srv.get_local_port()

	var d := Diorama.new()
	d.name = "SyncGateDiorama"
	tree.root.add_child(d)
	await tree.process_frame
	d.call("build")

	var hud := Playable.new()
	hud.name = "SyncGateHud"
	d.add_child(hud)
	await tree.process_frame

	var attach_state := {"done": false}
	var run_attach := func() -> void:
		await hud.call("_attach", "127.0.0.1:%d" % port)
		attach_state["done"] = true
	run_attach.call()

	var peer: StreamPeerTCP = null
	var buf := PackedByteArray()
	var framing := Framing.new()
	var held_snap_id: Variant = null
	var pre_baseline_methods: Array[String] = []
	var post_baseline_actions := 0
	var snap0 := {"tick": 0}
	var snap0_canon := StateDigest.canonical_state_hash(snap0)
	var tick1 := {"tick": 1}
	var tick1_canon := StateDigest.canonical_state_hash(tick1)

	# Pump until snapshot RPC arrives, holding the snapshot response open.
	for _i in range(240):
		if srv.is_connection_available() and peer == null:
			peer = srv.take_connection()
			peer.set_no_delay(true)
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								var m := msg as Dictionary
								var meth := String(m.get("method", ""))
								if meth == "initialize":
									peer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": m.get("id", 1),
										"result": {
											"serverName": "mock",
											"engineVersion": "0.0.0",
											"digest_spec_version": 2,
											"capabilities": {"hashes": true, "canonicalHashes": true, "audio": true},
											"tick": 0,
										},
									}))
								elif meth == "snapshot":
									held_snap_id = m.get("id", 2)
								else:
									pre_baseline_methods.append(meth)
		if held_snap_id != null:
			break
		await tree.process_frame

	t.check(held_snap_id != null, "Playable sent initial snapshot request and is waiting for baseline")
	var client_node: Node = hud.get("client")
	var session_node: Node = hud.get("session")
	var status_lbl: Label = hud.get("_status")
	t.is_true(client_node.has_method("has_baseline"), "NetworkClient exposes has_baseline()")
	t.is_false(bool(client_node.call("has_baseline")) if client_node.has_method("has_baseline") else false,
		"has_baseline() is false before snapshot returns")
	t.is_true(session_node.has_method("is_syncing"), "Session exposes is_syncing()")
	t.is_true(bool(session_node.call("is_syncing")) if session_node.has_method("is_syncing") else false,
		"session.is_syncing() is true before snapshot returns")
	t.contains(status_lbl.text.to_lower(), "syncing", "HUD status visibly displays syncing while baseline is in flight")

	# Exercise play input paths while snapshot is still held: key press, iso move, session.walk_to, client.submit_action.
	var key_walk := InputEventKey.new()
	key_walk.keycode = KEY_1
	key_walk.pressed = true
	hud.call("_input", key_walk)
	hud.call("_on_iso_move", "weighing-floor")

	var pre_req := {"walk_done": false, "walk_res": {}, "sub_done": false, "sub_res": {}}
	var run_pre_calls := func() -> void:
		pre_req["walk_res"] = await session_node.call("walk_to", "weighing-floor")
		pre_req["walk_done"] = true
		pre_req["sub_res"] = await client_node.call("submit_action", "look")
		pre_req["sub_done"] = true
	run_pre_calls.call()

	for _f in range(30):
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								var pm := msg as Dictionary
								var pmeth := String(pm.get("method", ""))
								pre_baseline_methods.append(pmeth)
								# Answer unexpected pre-baseline RPCs so RED fails fast without hitting a 20s timeout.
								peer.put_data(Framing.encode({
									"jsonrpc": "2.0",
									"id": pm.get("id", 99),
									"result": {"tick": 0, "events": []},
								}))
		if bool(pre_req["walk_done"]) and bool(pre_req["sub_done"]):
			break
		await tree.process_frame

	var pre_walk_res: Dictionary = pre_req["walk_res"] as Dictionary
	var pre_submit_res: Dictionary = pre_req["sub_res"] as Dictionary
	t.is_true(bool(pre_walk_res.get("__error__", false)), "session.walk_to refused before baseline snapshot")
	t.is_true(bool(pre_submit_res.get("__error__", false)), "client.submit_action refused before baseline snapshot")
	t.equals(pre_baseline_methods.size(), 0, "no play RPC frames transmitted before baseline snapshot lands")
	t.contains(status_lbl.text.to_lower(), "syncing", "HUD status remains in syncing state after refused pre-baseline input")

	# Release the baseline snapshot response.
	if peer != null and held_snap_id != null:
		peer.put_data(Framing.encode({
			"jsonrpc": "2.0",
			"id": held_snap_id,
			"result": {
				"tick": 0,
				"hash": "snap0",
				"canonicalHash": snap0_canon,
				"snapshotSeq": 1,
				"delta": [{"op": "set", "path": ["tick"], "value": 0}],
			},
		}))

	for _w in range(180):
		if bool(attach_state["done"]):
			break
		await tree.process_frame

	t.is_true(bool(attach_state["done"]), "Playable._attach finishes once baseline snapshot lands")
	t.is_true(client_node.has_method("has_baseline") and bool(client_node.call("has_baseline")), "has_baseline() becomes true after snapshot lands")
	t.is_false(bool(session_node.call("is_syncing")) if session_node.has_method("is_syncing") else true, "session.is_syncing() clears after snapshot lands")
	t.contains(status_lbl.text.to_lower(), "attached", "HUD status clears syncing and shows attached once ready")

	# Now press KEY_1 on the HUD: accepted, sent as submitAction, and digest-verified.
	hud.call("_input", key_walk)
	for _p in range(180):
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								var m := msg as Dictionary
								if String(m.get("method", "")) == "submitAction":
									post_baseline_actions += 1
									peer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": m.get("id", 3),
										"result": {
											"tick": 1,
											"hash": "tick1",
											"canonicalHash": tick1_canon,
											"snapshotSeq": 1,
											"delta": [{"op": "set", "path": ["tick"], "value": 1}],
											"events": [],
										},
									}))
		if post_baseline_actions >= 1 and not bool(hud.get("_busy")):
			break
		await tree.process_frame

	t.equals(post_baseline_actions, 1, "play input after baseline snapshot is accepted and sent")
	t.equals(String(client_node.call("mirror_digest")), tick1_canon, "post-baseline play submit is canonical-digest verified")
	t.is_false(bool(client_node.call("is_halted")), "post-baseline accepted input verifies cleanly without halting")
	t.is_false(bool(client_node.call("is_stale")), "post-baseline accepted input stays non-stale")

	if peer != null:
		peer.disconnect_from_host()
	srv.stop()
	hud.queue_free()
	d.queue_free()
	await tree.process_frame

	# 3. Live sidecar verification: input refused before snapshot, accepted + digest-verified after snapshot.
	var harness: RefCounted = Harness.new()
	var extra: Array[String] = [
		"--content", Harness.salt_road_pack(),
		"--manifest", Harness.salt_road_manifest(),
		"--start", Diorama.PLAYER_START_ZONE,
	]
	harness.extra_args = extra
	if not await harness.call("start", HOST_PACK, SEED):
		t.check(false, "live sidecar started for pre-baseline test", String(harness.get("failure")))
		return

	var lbus := EventBus.new()
	var lclient := NetworkClient.new()
	lclient.bus = lbus
	tree.root.add_child(lbus)
	tree.root.add_child(lclient)

	var ld := Diorama.new()
	tree.root.add_child(ld)
	await tree.process_frame
	ld.call("build")

	var lsession := Session.new()
	tree.root.add_child(lsession)
	lsession.call("setup", ld, lclient, lbus)

	var lhandshake: Dictionary = await lclient.call("attach", Harness.HOST, int(harness.get("port")), "stage/test-sync-gate", "0.1.0")
	t.is_false(lhandshake.is_empty(), "live pre-baseline handshake succeeded")
	t.is_false(bool(lclient.call("has_baseline")) if lclient.has_method("has_baseline") else true, "live client has no baseline immediately after attach")
	t.is_true(lsession.has_method("is_syncing") and bool(lsession.call("is_syncing")), "live session reports syncing immediately after attach")

	var refused_walk: Dictionary = await lsession.call("walk_to", "weighing-floor")
	t.is_true(bool(refused_walk.get("__error__", false)), "live session.walk_to refused before snapshot")
	t.contains(String(refused_walk.get("message", "")).to_lower(), "syncing", "live refusal explains syncing state")
	t.equals(String(lsession.call("player_zone")), Diorama.PLAYER_START_ZONE, "player zone unchanged after pre-baseline refusal")

	var refused_adv: Dictionary = await lsession.call("advance")
	t.is_true(bool(refused_adv.get("__error__", false)), "live session.advance refused before snapshot")

	var lsnap: Dictionary = await lclient.call("snapshot")
	t.is_false(bool(lsnap.get("__error__", false)), "live baseline snapshot succeeded")
	t.is_true(lclient.has_method("has_baseline") and bool(lclient.call("has_baseline")), "live client has baseline after snapshot")
	t.is_false(bool(lsession.call("is_syncing")) if lsession.has_method("is_syncing") else true, "live session clears syncing after snapshot")

	var accepted_walk: Dictionary = await lsession.call("walk_to", "weighing-floor")
	t.is_false(bool(accepted_walk.get("__error__", false)), "live session.walk_to accepted after baseline snapshot")
	t.equals(String(lsession.call("player_zone")), "weighing-floor", "player moved cleanly after baseline snapshot")
	t.equals(String(lclient.call("mirror_digest")), String(lclient.call("canonical_hash_for_tick", int(lclient.call("current_tick")))),
		"live post-baseline move verified canonical digest cleanly")
	t.equals(int(lclient.call("total_resyncs")), 0, "live post-baseline move required 0 resyncs")

	lclient.call("detach")
	lsession.queue_free()
	ld.queue_free()
	lclient.queue_free()
	lbus.queue_free()
	harness.call("stop")
	await tree.create_timer(0.3).timeout


func _test_a2_edge_paths_and_tick_dedup(t: RefCounted, tree: SceneTree) -> void:
	var srv := TCPServer.new()
	if srv.listen(0, "127.0.0.1") != OK:
		t.check(false, "mock server listening for edge-path tests", "TCPServer.listen failed")
		return
	var port := srv.get_local_port()

	# Helper closure state driven per test scenario on sequential client connections.
	var snap0 := {"items": []}
	var snap0_canon := StateDigest.canonical_state_hash(snap0)
	var tick1 := {"items": ["seal"]}
	var tick1_canon := StateDigest.canonical_state_hash(tick1)
	var tick2 := {"items": ["seal", "lantern"]}
	var tick2_canon := StateDigest.canonical_state_hash(tick2)

	# ── 1. Direct _on_tick non-idempotent append-patch dedup + halt guard in Playable._input ──
	var d := Diorama.new()
	tree.root.add_child(d)
	await tree.process_frame
	d.call("build")

	var hud := Playable.new()
	d.add_child(hud)
	await tree.process_frame

	var attach_state := {"done": false}
	var run_attach := func() -> void:
		await hud.call("_attach", "127.0.0.1:%d" % port)
		attach_state["done"] = true
	run_attach.call()

	var peer: StreamPeerTCP = null
	var buf := PackedByteArray()
	var framing := Framing.new()
	var rpc_methods_seen: Array[String] = []
	for _i in range(240):
		if srv.is_connection_available() and peer == null:
			peer = srv.take_connection()
			peer.set_no_delay(true)
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								var m := msg as Dictionary
								var meth := String(m.get("method", ""))
								if meth == "initialize":
									peer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": m.get("id", 1),
										"result": {
											"serverName": "mock",
											"engineVersion": "0.0.0",
											"digest_spec_version": 2,
											"capabilities": {"hashes": true, "canonicalHashes": true, "audio": true},
											"tick": 0,
										},
									}))
								elif meth == "snapshot":
									peer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": m.get("id", 2),
										"result": {
											"tick": 0,
											"hash": "h0",
											"canonicalHash": snap0_canon,
											"snapshotSeq": 1,
											"delta": [{"op": "add", "path": [], "value": {"items": []}}],
										},
									}))
		if bool(attach_state["done"]):
			break
		await tree.process_frame

	t.is_true(bool(attach_state["done"]), "edge-path HUD attached and baselined")
	var client: Node = hud.get("client")
	var bus: Node = hud.get("bus")

	# Non-idempotent append patch via submitAction response, followed by matching sim/tick notification.
	var append_delta := [{"op": "set", "path": ["items", "-"], "value": "seal"}]
	var sub_state := {"done": false, "res": {}}
	var run_sub := func() -> void:
		sub_state["res"] = await client.call("submit_action", "look")
		sub_state["done"] = true
	run_sub.call()

	for _f in range(180):
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								var m := msg as Dictionary
								if String(m.get("method", "")) == "submitAction":
									peer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": m.get("id", 3),
										"result": {
											"tick": 1,
											"hash": "h1",
											"canonicalHash": tick1_canon,
											"snapshotSeq": 1,
											"delta": append_delta,
											"events": [],
										},
									}))
		if bool(sub_state["done"]):
			break
		await tree.process_frame

	t.is_false(bool((sub_state["res"] as Dictionary).get("__error__", false)), "append submitAction succeeded")
	# Deliver the matching sim/tick notification for tick 1 after submitAction already applied via RPC.
	if peer != null:
		peer.put_data(Framing.encode({
			"jsonrpc": "2.0",
			"method": "sim/tick",
			"params": {
				"tick": 1,
				"hash": "h1",
				"canonicalHash": tick1_canon,
				"snapshotSeq": 1,
				"delta": append_delta,
				"events": [],
			},
		}))
	for _p in range(6):
		await tree.process_frame

	var items_after_dedup: Array = ((client.call("mirror_state") as Dictionary).get("items", []) as Array)
	t.equals(items_after_dedup.size(), 1, "_on_tick skips duplicate append patch already applied via submitAction RPC")
	t.equals(items_after_dedup, ["seal"], "mirror preserves single 'seal' item rather than double-appending")
	t.equals(String(client.call("mirror_digest")), tick1_canon, "canonical digest agrees after duplicate sim/tick")

	# A genuinely new sim/tick (tick 2, appending 'lantern') IS applied by _on_tick.
	if peer != null:
		peer.put_data(Framing.encode({
			"jsonrpc": "2.0",
			"method": "sim/tick",
			"params": {
				"tick": 2,
				"hash": "h2",
				"canonicalHash": tick2_canon,
				"snapshotSeq": 1,
				"delta": [{"op": "set", "path": ["items", "-"], "value": "lantern"}],
				"events": [],
			},
		}))
	for _p2 in range(6):
		await tree.process_frame
	var items_after_new_tick: Array = ((client.call("mirror_state") as Dictionary).get("items", []) as Array)
	t.equals(items_after_new_tick, ["seal", "lantern"], "_on_tick applies genuinely new tick delta")
	t.equals(String(client.call("mirror_digest")), tick2_canon, "canonical digest updates on genuinely new sim/tick")

	# ── 2. Canonical serialization error branch inside verify_position() ──
	# Inject a non-ASCII key locally while tick=2 and JS hash="h2" still agree so drift_reason
	# only trips via StateDigest.try_canonical_json(_mirror) inside verify_position().
	var mdict := client.call("mirror_state") as Dictionary
	mdict["café"] = 1
	var verify_err_state := {"done": false, "agreed": true}
	var run_ver := func() -> void:
		verify_err_state["agreed"] = await client.call("verify_position")
		verify_err_state["done"] = true
	run_ver.call()

	for _v in range(180):
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								var vm := msg as Dictionary
								if String(vm.get("method", "")) == "snapshot":
									peer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": vm.get("id", 4),
										"result": {
											"tick": 2,
											"hash": "h2",
											"canonicalHash": tick2_canon,
											"snapshotSeq": 2,
											"delta": [{"op": "add", "path": [], "value": {"items": ["seal", "lantern"]}}],
										},
									}))
		if bool(verify_err_state["done"]):
			break
		await tree.process_frame

	t.is_true(bool(verify_err_state["done"]), "verify_position with canonical error completed")
	t.is_false(bool(verify_err_state["agreed"]), "verify_position returns false when mirror canonical serialization fails")
	var ver_logs: Array[String] = client.call("mismatch_log")
	t.check(ver_logs.size() >= 1 and ver_logs[0].contains("canonical serialization error"),
		"verify_position logs canonical serialization error into mismatch_log",
		str(ver_logs))
	t.equals(String(client.call("mirror_digest")), tick2_canon, "verify_position resyncs clean mirror after canonical error")

	# ── 3. Halt guard in Playable._input (KEY_1 + KEY_SPACE refused once halted) ──
	var log_before := (hud.get("_log") as RichTextLabel).text
	bus.session_halted.emit("cap exceeded")
	await tree.process_frame
	var key1 := InputEventKey.new()
	key1.keycode = KEY_1
	key1.pressed = true
	var key_space := InputEventKey.new()
	key_space.keycode = KEY_SPACE
	key_space.pressed = true
	hud.call("_input", key1)
	hud.call("_input", key_space)

	for _f3 in range(6):
		if peer != null:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := peer.get_available_bytes()
				if av > 0:
					var g := peer.get_partial_data(av)
					if int(g[0]) == OK:
						buf.append_array(g[1] as PackedByteArray)
						for msg: Variant in framing.push(buf):
							buf.clear()
							if msg is Dictionary:
								rpc_methods_seen.append(String((msg as Dictionary).get("method", "")))
		await tree.process_frame

	t.equals(rpc_methods_seen.size(), 0, "Playable._input transmits 0 RPCs for KEY_1/KEY_SPACE once halted")
	t.is_false(bool(hud.get("_busy")), "Playable._busy remains false after halted input")
	t.contains((hud.get("_status") as Label).text, "sync halted — cap exceeded", "Playable status shows halt reason")
	t.is_false((hud.get("_log") as RichTextLabel).text.substr(log_before.length()).contains("You wait."),
		"Playable._input skips _wait_a_round once halted")

	if peer != null:
		peer.disconnect_from_host()
	hud.queue_free()
	d.queue_free()
	await tree.process_frame

	# ── 4. Failed resync snapshot request inside _verify_mirror_after_submit ──
	var fbus := EventBus.new()
	var fclient := NetworkClient.new()
	fclient.bus = fbus
	fclient.set("suppress_ci_halt_marker", true)
	tree.root.add_child(fbus)
	tree.root.add_child(fclient)
	var fhalts: Array[String] = []
	fbus.session_halted.connect(func(r: String) -> void: fhalts.append(r))

	var frun_state := {"done": false}
	var run_fail_snap := func() -> void:
		await fclient.call("attach", "127.0.0.1", port, "stage/test-failed-resync-snap")
		await fclient.call("snapshot")
		await fclient.call("submit_action", "look")
		frun_state["done"] = true
	run_fail_snap.call()

	var fpeer: StreamPeerTCP = null
	var fbuf := PackedByteArray()
	var fframing := Framing.new()
	var snap_req_count := 0
	for _k in range(240):
		if srv.is_connection_available() and fpeer == null:
			fpeer = srv.take_connection()
			fpeer.set_no_delay(true)
		if fpeer != null:
			fpeer.poll()
			if fpeer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var av := fpeer.get_available_bytes()
				if av > 0:
					var g := fpeer.get_partial_data(av)
					if int(g[0]) == OK:
						fbuf.append_array(g[1] as PackedByteArray)
						for msg: Variant in fframing.push(fbuf):
							fbuf.clear()
							if msg is Dictionary:
								var fm := msg as Dictionary
								var fmeth := String(fm.get("method", ""))
								if fmeth == "initialize":
									fpeer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": fm.get("id", 1),
										"result": {
											"serverName": "mock",
											"engineVersion": "0.0.0",
											"digest_spec_version": 2,
											"capabilities": {"hashes": true, "canonicalHashes": true},
											"tick": 0,
										},
									}))
								elif fmeth == "snapshot":
									snap_req_count += 1
									if snap_req_count == 1:
										fpeer.put_data(Framing.encode({
											"jsonrpc": "2.0",
											"id": fm.get("id", 2),
											"result": {
												"tick": 0,
												"hash": "h0",
												"canonicalHash": snap0_canon,
												"snapshotSeq": 1,
												"delta": [{"op": "add", "path": [], "value": {"items": []}}],
											},
										}))
									else:
										fpeer.put_data(Framing.encode({
											"jsonrpc": "2.0",
											"id": fm.get("id", 4),
											"error": {"code": -32000, "message": "snapshot store unavailable"},
										}))
								elif fmeth == "submitAction":
									# Return mismatched canonicalHash so client attempts a resync snapshot.
									fpeer.put_data(Framing.encode({
										"jsonrpc": "2.0",
										"id": fm.get("id", 3),
										"result": {
											"tick": 1,
											"hash": "h1",
											"canonicalHash": "deadbeefdeadbeefdeadbeefdeadbeef",
											"snapshotSeq": 1,
											"delta": [],
										},
									}))
		if bool(frun_state["done"]):
			break
		await tree.process_frame

	t.is_true(bool(frun_state["done"]), "failed resync snapshot test completed")
	t.is_true(bool(fclient.call("is_halted")), "failed resync snapshot halts client")
	t.is_true(bool(fclient.call("is_stale")), "failed resync snapshot marks client stale")
	t.contains(String(fclient.call("halt_reason")), "resync snapshot failed: snapshot store unavailable",
		"halt_reason records failed resync snapshot error")
	t.equals(fhalts.size(), 1, "session_halted emits once on resync snapshot failure")
	var fmismatches: Array[String] = fclient.call("mismatch_log")
	t.check(fmismatches.size() == 1 and fmismatches[0].contains("resync snapshot failed: snapshot store unavailable"),
		"mismatch_log records failed resync snapshot", str(fmismatches))

	if fpeer != null:
		fpeer.disconnect_from_host()
	srv.stop()
	fclient.queue_free()
	fbus.queue_free()
	await tree.process_frame
