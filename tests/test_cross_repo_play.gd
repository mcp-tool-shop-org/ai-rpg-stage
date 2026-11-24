## test_cross_repo_play.gd — cross-repo Salt Road play check in stage CI.
##
## Attaches the stage headless to the engine sidecar loaded with the freshly exported
## Salt Road pack under `--unresolved-ai-profile fail` and plays 13 scripted steps —
## 11 walks (10 accepted zone moves plus 1 gated refusal) and 2 round advances (12
## accepted moves) — through `Session` (`walk_to` / `advance`). Asserts expected
## acceptance/refusal and zone, canonical digest equality, empty mismatch log, zero
## resyncs, and unhalted state after every move, then asserts accepted move count,
## refused move count, final tick, and closing snapshot agreement.
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const TestCase := preload("res://tools/test_case.gd")
const Diorama := preload("res://stage/diorama.gd")
const Session := preload("res://stage/session.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")

const HOST_PACK := "chapel-threshold"
const SEED := 71
const CUE := "dockward:stability:-25@2"
const EXPECTED_FINAL_ZONE := "long-quay"
const EXPECTED_FINAL_TICK := 11

const PLAY_SCRIPT: Array[Dictionary] = [
	{"kind": "walk", "zone": "weighing-floor", "accepted": true, "expected_zone": "weighing-floor"},
	{"kind": "walk", "zone": "bonded-warehouse", "accepted": false, "expected_zone": "weighing-floor"},
	{"kind": "walk", "zone": "long-quay", "accepted": true, "expected_zone": "long-quay"},
	{"kind": "advance", "accepted": true, "expected_zone": "long-quay"},
	{"kind": "advance", "accepted": true, "expected_zone": "long-quay"},
	{"kind": "walk", "zone": "customs-shed", "accepted": true, "expected_zone": "customs-shed"},
	{"kind": "walk", "zone": "long-quay", "accepted": true, "expected_zone": "long-quay"},
	{"kind": "walk", "zone": "crooked-stair", "accepted": true, "expected_zone": "crooked-stair"},
	{"kind": "walk", "zone": "long-quay", "accepted": true, "expected_zone": "long-quay"},
	{"kind": "walk", "zone": "weighing-floor", "accepted": true, "expected_zone": "weighing-floor"},
	{"kind": "walk", "zone": "counting-house", "accepted": true, "expected_zone": "counting-house"},
	{"kind": "walk", "zone": "weighing-floor", "accepted": true, "expected_zone": "weighing-floor"},
	{"kind": "walk", "zone": "long-quay", "accepted": true, "expected_zone": "long-quay"},
]


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "cross-repo play requires frames")
		return

	var pack_path := Harness.salt_road_pack()
	t.is_true(FileAccess.file_exists(pack_path),
		"exported Salt Road pack exists (%s)" % pack_path)
	var manifest_path := Harness.salt_road_manifest()
	t.is_true(FileAccess.file_exists(manifest_path),
		"Salt Road manifest exists (%s)" % manifest_path)
	if not FileAccess.file_exists(pack_path) or not FileAccess.file_exists(manifest_path):
		return

	var nonexistent_script: Array[Dictionary] = []
	for step_v: Variant in PLAY_SCRIPT:
		var s := (step_v as Dictionary).duplicate(true)
		if String(s.get("kind", "")) == "walk":
			s["zone"] = "nonexistent-harbour-zone"
		nonexistent_script.append(s)

	# 1. Clean 13-step play run (11 walks: 10 accepted + 1 gated refusal; plus 2 advances) under `fail`.
	var live_res: Dictionary = await _play_salt_road(t, tree, pack_path, manifest_path, "salt-road-live")
	t.check(int(live_res.get("accepted_moves", 0)) >= 10,
		"played at least 10 accepted moves cleanly through Session",
		"got %d" % int(live_res.get("accepted_moves", 0)))
	t.equals(int(live_res.get("refused_moves", 0)), 1,
		"recorded exact 1 asserted gated refusal in the scripted sequence")

	# 2. RED controls: prove refused walks never satisfy accepted-move count, and mid-run drift
	#    triggers mismatch_log / resync failures on clean-play assertions.
	var probe_refused: RefCounted = TestCase.new()
	var res_refused: Dictionary = await _play_salt_road(
		probe_refused,
		tree,
		pack_path,
		manifest_path,
		"salt-road-red-all-refused",
		[],
		false,
		nonexistent_script,
	)
	var refused_failures: Array = probe_refused.get("failures") as Array
	t.check(int(res_refused.get("accepted_moves", 0)) < 10,
		"RED control: refusing every walk leaves accepted move count below 10 (%d)" % int(res_refused.get("accepted_moves", 0)))
	t.check(refused_failures.size() > 0,
		"RED control: nonexistent-zone walks fail per-move acceptance and zone assertions",
		"expected non-zero probe failures")

	var probe_resync: RefCounted = TestCase.new()
	var res_single: Dictionary = await _play_salt_road(
		probe_resync,
		tree,
		pack_path,
		manifest_path,
		"salt-road-red-resync",
		[6],
		true,
	)
	var single_failures: Array = probe_resync.get("failures") as Array
	var saw_mismatch_fail := false
	for fmsg: Variant in single_failures:
		if String(fmsg).contains("mismatch_log is empty"):
			saw_mismatch_fail = true
	t.equals(int(res_single.get("total_resyncs", 0)), 1,
		"RED control: mid-run digest corruption triggers snapshot resync")
	t.is_true(saw_mismatch_fail,
		"RED control: mid-run drift fails per-move mismatch_log assertion")
	t.check(single_failures.size() > 0,
		"RED control: mid-run resync fails the clean-play assertions",
		"expected non-zero probe failures")

	var probe_halt: RefCounted = TestCase.new()
	var res_halt: Dictionary = await _play_salt_road(
		probe_halt,
		tree,
		pack_path,
		manifest_path,
		"salt-road-red-halt",
		[5, 6, 7, 8],
		true,
	)
	var halt_failures: Array = probe_halt.get("failures") as Array
	t.is_true(bool(res_halt.get("halted", false)),
		"RED control: 4 consecutive mid-run corruptions halt play")
	t.check(halt_failures.size() > 0,
		"RED control: mid-run halt fails the clean-play assertions",
		"expected non-zero probe failures")


func _play_salt_road(
	case_t: RefCounted,
	tree: SceneTree,
	pack_path: String,
	manifest_path: String,
	label: String,
	corrupt_before_moves: Array[int] = [],
	suppress_halt_marker: bool = false,
	script_steps: Array[Dictionary] = PLAY_SCRIPT,
) -> Dictionary:
	var harness: RefCounted = Harness.new()
	harness.set("unresolved_ai_profile_override", "fail")
	case_t.equals(String(harness.call("effective_unresolved_profile_mode")), "fail",
		"%s: launches sidecar with unresolved-ai-profile fail" % label)
	var extra: Array[String] = [
		"--content", pack_path,
		"--manifest", manifest_path,
		"--start", Diorama.PLAYER_START_ZONE,
		"--shock", CUE,
	]
	harness.set("extra_args", extra)

	var started: bool = await harness.call("start", HOST_PACK, SEED)
	if not started:
		case_t.check(false, "%s: sidecar starts with exported Salt Road pack under fail" % label,
			String(harness.get("failure")))
		harness.call("stop")
		harness.call("cleanup_stderr_file")
		return {"accepted_moves": 0, "refused_moves": 0, "final_tick": -1, "total_resyncs": 0, "halted": false}

	var bus := EventBus.new()
	bus.name = "CrossBus_%s" % label
	tree.root.add_child(bus)

	var client := NetworkClient.new()
	client.name = "CrossClient_%s" % label
	client.bus = bus
	client.set("suppress_ci_halt_marker", suppress_halt_marker)
	tree.root.add_child(client)

	var d := Diorama.new()
	d.name = "CrossDiorama_%s" % label
	tree.root.add_child(d)
	await tree.process_frame
	d.call("build")

	var session := Session.new()
	session.name = "CrossSession_%s" % label
	tree.root.add_child(session)
	session.call("setup", d, client, bus)

	var handshake: Dictionary = await client.call("attach", Harness.HOST, int(harness.get("port")), "stage/%s" % label, "0.1.0")
	case_t.is_false(handshake.is_empty(), "%s: attach handshake completes" % label)
	if handshake.is_empty():
		await _teardown(harness, session, d, client, bus, tree)
		return {"accepted_moves": 0, "refused_moves": 0, "final_tick": -1, "total_resyncs": 0, "halted": false}

	case_t.equals(int(handshake.get("digest_spec_version", 0)), 2,
		"%s: server reports digest_spec_version 2" % label)
	var caps: Dictionary = handshake.get("capabilities", {}) as Dictionary
	case_t.is_true(bool(caps.get("canonicalHashes", false)),
		"%s: handshake negotiates capabilities.canonicalHashes" % label)

	var snap: Dictionary = await client.call("snapshot")
	case_t.is_false(bool(snap.get("__error__", false)), "%s: baseline snapshot succeeds" % label)
	case_t.is_true(bool(client.call("has_baseline")), "%s: client has baseline after snapshot" % label)
	case_t.is_false(bool(session.call("is_syncing")), "%s: session exits syncing state after snapshot" % label)
	case_t.equals(String(client.call("mirror_digest")), String(snap.get("canonicalHash", "")),
		"%s: initial mirror digest matches baseline canonicalHash" % label)

	var initial_tick := int(snap.get("tick", -1))
	case_t.equals(initial_tick, 0, "%s: initial snapshot tick is 0" % label)

	await tree.process_frame

	var accepted_moves := 0
	var refused_moves := 0
	var expected_accepted := 0
	var expected_refused := 0
	for idx in range(script_steps.size()):
		var move_no := idx + 1
		var step: Dictionary = script_steps[idx]
		var kind := String(step.get("kind", ""))
		var expect_accepted := bool(step.get("accepted", true))
		var expect_zone := String(step.get("expected_zone", ""))
		if expect_accepted:
			expected_accepted += 1
		else:
			expected_refused += 1

		if corrupt_before_moves.has(move_no):
			client.call("_debug_corrupt_recorded_hash", int(client.call("current_tick")))

		var result: Dictionary = {}
		if kind == "walk":
			result = await session.call("walk_to", String(step.get("zone", "")))
		else:
			result = await session.call("advance")

		var failed_call := bool(result.get("__error__", false))
		case_t.is_false(failed_call, "%s move %d (%s): play submit completes without wire error" % [label, move_no, kind])

		var events: Array = result.get("events", []) as Array
		var saw_entered := false
		var saw_refused := false
		for ev_v: Variant in events:
			if ev_v is Dictionary:
				var ev_type := String((ev_v as Dictionary).get("type", ""))
				if ev_type == "world.zone.entered":
					saw_entered = true
				elif ev_type == "action.rejected" or ev_type == "world.zone.gate.refused":
					saw_refused = true

		var was_accepted := (not failed_call and saw_entered and not saw_refused) if kind == "walk" else (not failed_call and not saw_refused)
		var was_refused := (not failed_call and saw_refused and not saw_entered) if kind == "walk" else (not failed_call and saw_refused)

		if was_accepted:
			accepted_moves += 1
		elif was_refused:
			refused_moves += 1

		if expect_accepted:
			case_t.is_true(was_accepted,
				"%s move %d (%s): move accepted as expected" % [label, move_no, kind])
		else:
			case_t.is_true(was_refused,
				"%s move %d (%s): gated move refused as expected" % [label, move_no, kind])
		case_t.equals(String(session.call("player_zone")), expect_zone,
			"%s move %d: player_zone matches expected '%s'" % [label, move_no, expect_zone])

		var move_tick := int(result.get("tick", -1))
		var engine_digest := String(result.get("canonicalHash", ""))
		var stage_digest := String(client.call("mirror_digest"))
		var recorded_digest := String(client.call("canonical_hash_for_tick", move_tick))

		case_t.is_false(engine_digest.is_empty(),
			"%s move %d: engine returned non-empty canonicalHash for tick %d" % [label, move_no, move_tick])
		case_t.equals(stage_digest, engine_digest,
			"%s move %d (tick %d): stage digest equals engine canonicalHash" % [label, move_no, move_tick])
		case_t.equals(stage_digest, recorded_digest,
			"%s move %d (tick %d): stage digest matches recorded tick digest" % [label, move_no, move_tick])
		case_t.equals((client.call("mismatch_log") as Array).size(), 0,
			"%s move %d: mismatch_log is empty" % [label, move_no])
		case_t.equals(int(client.call("total_resyncs")), 0,
			"%s move %d: no resync occurred" % [label, move_no])
		case_t.equals(int(client.call("consecutive_resyncs")), 0,
			"%s move %d: consecutive resync streak is 0" % [label, move_no])
		case_t.is_false(bool(client.call("is_stale")),
			"%s move %d: client mirror not stale" % [label, move_no])
		case_t.is_false(bool(client.call("is_halted")),
			"%s move %d: client not halted" % [label, move_no])
		case_t.is_false(bool(session.call("is_halted")),
			"%s move %d: session not halted" % [label, move_no])

	var final_tick := int(client.call("current_tick"))
	var total_resyncs_end := int(client.call("total_resyncs"))
	var halted_end := bool(client.call("is_halted"))

	case_t.equals(accepted_moves, expected_accepted,
		"%s: completed all %d accepted moves" % [label, expected_accepted])
	case_t.equals(refused_moves, expected_refused,
		"%s: observed exact %d asserted gated refusal(s)" % [label, expected_refused])
	case_t.check(final_tick > initial_tick,
		"%s: final tick (%d) advanced past initial tick (%d)" % [label, final_tick, initial_tick],
		"initial=%d, final=%d" % [initial_tick, final_tick])
	case_t.equals(final_tick, EXPECTED_FINAL_TICK,
		"%s: final tick equals deterministic target %d" % [label, EXPECTED_FINAL_TICK])
	case_t.equals(String(session.call("player_zone")), EXPECTED_FINAL_ZONE,
		"%s: player finishes at expected destination zone (%s)" % [label, EXPECTED_FINAL_ZONE])

	if not halted_end:
		var closing_snap: Dictionary = await client.call("snapshot")
		case_t.is_false(bool(closing_snap.get("__error__", false)),
			"%s: closing snapshot succeeds" % label)
		case_t.equals(final_tick, int(closing_snap.get("tick", -1)),
			"%s: final client tick matches engine snapshot tick" % label)
		case_t.equals(String(client.call("mirror_digest")), String(closing_snap.get("canonicalHash", "")),
			"%s: final stage digest matches closing snapshot canonicalHash" % label)

	await _teardown(harness, session, d, client, bus, tree)
	return {
		"accepted_moves": accepted_moves,
		"refused_moves": refused_moves,
		"final_tick": final_tick,
		"total_resyncs": total_resyncs_end,
		"halted": halted_end,
	}


func _teardown(
	harness: RefCounted,
	session: Node,
	d: Node2D,
	client: Node,
	bus: Node,
	tree: SceneTree,
) -> void:
	if client != null:
		client.call("detach")
		client.queue_free()
	if session != null:
		session.queue_free()
	if d != null:
		d.queue_free()
	if bus != null:
		bus.queue_free()
	if harness != null:
		harness.call("stop")
		harness.call("cleanup_stderr_file")
	await tree.create_timer(0.4).timeout
