## test_cross_repo_play.gd — cross-repo Salt Road play check in stage CI.
##
## Attaches the stage headless to the engine sidecar loaded with the freshly exported
## Salt Road pack under `--unresolved-ai-profile fail` and plays a 12-step sequence
## (10 zone moves plus 2 round advances) through `Session` (`walk_to` / `advance`).
## Asserts canonical digest equality, zero resyncs, and unhalted state after every
## move, then asserts final move count, final tick, and closing snapshot agreement.
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
const EXPECTED_FINAL_ZONE := "weighing-floor"
const EXPECTED_FINAL_TICK := 10

const PLAY_SCRIPT: Array[Dictionary] = [
	{"kind": "walk", "zone": "weighing-floor"},
	{"kind": "walk", "zone": "bonded-warehouse"},
	{"kind": "walk", "zone": "long-quay"},
	{"kind": "advance"},
	{"kind": "advance"},
	{"kind": "walk", "zone": "customs-shed"},
	{"kind": "walk", "zone": "long-quay"},
	{"kind": "walk", "zone": "crooked-stair"},
	{"kind": "walk", "zone": "long-quay"},
	{"kind": "walk", "zone": "weighing-floor"},
	{"kind": "walk", "zone": "counting-house"},
	{"kind": "walk", "zone": "weighing-floor"},
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

	# 1. Clean 12-move play run under `--unresolved-ai-profile fail`.
	var live_res: Dictionary = await _play_salt_road(t, tree, pack_path, manifest_path, "salt-road-live")
	t.check(int(live_res.get("moves_completed", 0)) >= 10,
		"played at least 10 moves cleanly through Session",
		"got %d" % int(live_res.get("moves_completed", 0)))

	# 2. Mid-run planted corruption controls: prove the suite's per-move assertions fail
	#    if mirror state drifts and triggers a resync or consecutive-cap halt.
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
	t.equals(int(res_single.get("total_resyncs", 0)), 1,
		"RED control: mid-run digest corruption triggers snapshot resync")
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
		return {"moves_completed": 0, "final_tick": -1, "total_resyncs": 0, "halted": false}

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
		return {"moves_completed": 0, "final_tick": -1, "total_resyncs": 0, "halted": false}

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

	var moves_completed := 0
	for idx in range(PLAY_SCRIPT.size()):
		var move_no := idx + 1
		var step: Dictionary = PLAY_SCRIPT[idx]
		var kind := String(step.get("kind", ""))

		if corrupt_before_moves.has(move_no):
			client.call("_debug_corrupt_recorded_hash", int(client.call("current_tick")))

		var result: Dictionary = {}
		if kind == "walk":
			result = await session.call("walk_to", String(step.get("zone", "")))
		else:
			result = await session.call("advance")

		var failed_call := bool(result.get("__error__", false))
		case_t.is_false(failed_call, "%s move %d (%s): play submit succeeds" % [label, move_no, kind])
		if not failed_call:
			moves_completed += 1

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

	case_t.equals(moves_completed, PLAY_SCRIPT.size(),
		"%s: completed all %d scripted moves" % [label, PLAY_SCRIPT.size()])
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
		"moves_completed": moves_completed,
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
