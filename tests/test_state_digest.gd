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
	for case_spec: Dictionary in [
		{"label": "unsupported v1", "result": {"serverName": "mock", "engineVersion": "0.0.0", "digest_spec_version": 1, "capabilities": {"hashes": true, "canonicalHashes": true}}, "expect": "unsupported digest_spec_version"},
		{"label": "missing version", "result": {"serverName": "mock", "engineVersion": "0.0.0", "capabilities": {"hashes": true, "canonicalHashes": true}}, "expect": "unsupported digest_spec_version"},
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

	var verified_now: bool = await client.call("verify_position")
	t.is_true(verified_now, "subsequent verify_position() agrees after snapshot resync")
	t.equals(int(client.call("consecutive_resyncs")), 0, "clean verify resets consecutive resync streak")

	# Another clean play move confirms consecutive resync counter stays 0.
	await session.call("walk_to", "customs-shed")
	t.equals(int(client.call("consecutive_resyncs")), 0, "consecutive resync counter remains 0 on clean submit")
	t.is_false(bool(client.call("is_stale")), "clean submit clears stale state")

	# 2. Four consecutive forced mismatches trip the 3-resync cap and halt play with visible error.
	var halted_events: Array[String] = []
	bus.session_halted.connect(func(reason: String) -> void: halted_events.append(reason))
	client.suppress_ci_halt_marker = true

	for attempt in range(1, 5):
		client.call("_debug_corrupt_recorded_hash", int(client.call("current_tick")))
		await session.call("advance")
		if attempt <= 3:
			t.is_false(bool(client.call("is_halted")),
				"resync %d/3 remains within the consecutive cap" % attempt)
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
