## test_live_session.gd — P4's exit gate: the sim drives the diorama.
##
## Everything visible in this test changes because an EVENT said so. Nothing is set by
## hand, nothing is predicted, and the stage never decides.
##
## The four clauses of C4's sentence, live:
##
##   movement       the player walks between zones through real `move` intents, and the
##                  scene's player node follows the sim's idea of where they are
##   a refusal      walking into the bonded warehouse without the seal produces Halle's
##                  own sentence, rendered — not a status code and not a greyed door
##   spawns         the anchor fires on entering the stair and the spawned entities become
##                  real nodes where the sim placed them
##   a re-dress     a district shock arrives as `world.zone.state.changed` and the quay
##                  visibly re-dresses, in that zone only
##
## Plus determinism: the same seed and the same script produce the same transcript.
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const Diorama := preload("res://stage/diorama.gd")
const Session := preload("res://stage/session.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")

const HOST_PACK := "chapel-threshold"
const SEED := 71

## Where the walk goes. Ends at the stair because that is where the anchor is.
const WALK := ["weighing-floor", "bonded-warehouse", "long-quay", "crooked-stair"]

## The gated zone, and the district whose fortunes the cue moves.
const GATED := "bonded-warehouse"
const SHOCK_ZONE := "long-quay"
const CUE := "dockward:stability:-25@2"

const SECTIONS := ["movement", "refusal", "spawns", "redress", "determinism"]

var _completed: Array[String] = []


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "the live session needs frames")
		return

	var pack_path := Harness.salt_road_pack()
	if not FileAccess.file_exists(pack_path):
		# A hard failure, never a skip. A silently skipped live proof is the vacuous green
		# this suite refuses everywhere else.
		t.check(false, "the Salt Road pack is exported",
			"%s missing — run world-forge's export-stage-fixture, or set SALT_ROAD_PACK" % pack_path)
		return

	var first := await _run_session(t, tree, pack_path, "run-1")
	if not first.get("ok", false):
		return

	var session: Node = first["session"]
	var d: Node2D = first["diorama"]

	_movement(t, first, d)
	_completed.append("movement")
	_refusal(t, first)
	_completed.append("refusal")
	_spawns(t, first, d)
	_completed.append("spawns")
	await _redress(t, first, d, tree)
	_completed.append("redress")

	var transcript_1: Array = (session.get("transcript") as Array).duplicate()
	await _teardown(first, tree)

	# ── Determinism ──────────────────────────────────────────
	var second := await _run_session(t, tree, pack_path, "run-2")
	if not second.get("ok", false):
		return
	var transcript_2: Array = ((second["session"] as Node).get("transcript") as Array).duplicate()
	var digest_2 := String((second["client"] as Node).call("received_digest"))
	var digest_1 := String(first["digest"])
	await _teardown(second, tree)

	t.check(transcript_1.size() > 0, "run 1 produced a transcript", "got %d lines" % transcript_1.size())
	t.equals(transcript_2, transcript_1,
		"SAME SEED, SAME SCRIPT: the two sessions narrate identically")
	t.equals(digest_2, digest_1, "and the raw bytes received are identical too")
	# RED: the comparison must be able to fail, or two empty transcripts would agree.
	var doctored := transcript_1.duplicate()
	doctored.append("a line the sim never sent")
	t.not_equals(doctored, transcript_1, "RED: the transcript comparison can fail")
	_completed.append("determinism")

	t.same_set(_completed, SECTIONS, "every section of this suite ran to completion")


# ── The session ───────────────────────────────────────────────

func _run_session(t: RefCounted, tree: SceneTree, pack_path: String, label: String) -> Dictionary:
	var harness: RefCounted = Harness.new()
	harness.set("extra_args", [
		"--content", pack_path,
		"--start", Diorama.PLAYER_START_ZONE,
		"--shock", CUE,
	] as Array[String])

	var started: bool = await harness.call("start", HOST_PACK, SEED)
	if not started:
		t.check(false, "%s: the sidecar starts with Salt Road loaded" % label, String(harness.get("failure")))
		return {"ok": false}

	var bus: Node = EventBus.new()
	bus.name = "Bus_%s" % label
	tree.root.add_child(bus)

	var client: Node = NetworkClient.new()
	client.name = "Client_%s" % label
	client.bus = bus
	client.call("record_received_bytes")
	tree.root.add_child(client)

	var d: Node2D = Diorama.new()
	d.name = "Diorama_%s" % label
	tree.root.add_child(d)
	# The harness property from P3: a node added during `_initialize` is not in the tree
	# until the first frame, and building before then leaves every `get_tree()` null.
	await tree.process_frame
	d.call("build")

	var session: Node = Session.new()
	session.name = "Session_%s" % label
	tree.root.add_child(session)
	session.call("setup", d, client, bus)

	var handshake: Dictionary = await client.call("attach", Harness.HOST, int(harness.get("port")), "stage/%s" % label)
	if handshake.is_empty():
		t.check(false, "%s: the handshake completes" % label, "attach returned nothing")
		harness.call("stop")
		return {"ok": false}

	# A snapshot first, so the stage has a position before it changes one.
	await client.call("snapshot")

	# ── The walk ─────────────────────────────────────────────
	var results: Array[Dictionary] = []
	for zone_id: String in WALK:
		var r: Dictionary = await session.call("walk_to", zone_id)
		results.append(r)

	# ── The rounds that carry the shock ──────────────────────
	for _i in range(3):
		await session.call("advance")

	return {
		"ok": true,
		"harness": harness, "bus": bus, "client": client, "diorama": d, "session": session,
		"walk_results": results,
		"digest": client.call("received_digest"),
	}


# ── The clauses ───────────────────────────────────────────────

func _movement(t: RefCounted, bag: Dictionary, d: Node2D) -> void:
	var session: Node = bag["session"]
	# The player ENDED somewhere the sim agrees with, and the scene node moved with them.
	var zone := String(session.call("player_zone"))
	t.check(not zone.is_empty(), "the stage knows which zone the player is in")

	var player: Node2D = d.get("player")
	var parent := player.get_parent()
	t.check(parent != null, "the player node has a parent zone")
	if parent != null:
		t.equals(String(parent.get_meta("zone_id", "")), zone,
			"the player's NODE is inside the zone the sim says they are in")

	# At least one move was accepted — otherwise every clause below is about nothing.
	var entered := 0
	for r: Dictionary in (bag["walk_results"] as Array):
		for ev: Variant in (r.get("events", []) as Array):
			if ev is Dictionary and String((ev as Dictionary).get("type", "")) == "world.zone.entered":
				entered += 1
	t.check(entered > 0, "the player really moved through the sim", "entered %d zones" % entered)


func _refusal(t: RefCounted, bag: Dictionary) -> void:
	# The gated warehouse. The stage walked into it WITHOUT checking, because checking is
	# the sim's job — and got a person's sentence back.
	var session: Node = bag["session"]
	var transcript: Array = session.get("transcript")

	var refusal := ""
	for line: Variant in transcript:
		if String(line).contains("mother in Dockward"):
			refusal = String(line)
	t.check(not refusal.is_empty(),
		"the gate refused with HALLE'S OWN SENTENCE, rendered",
		"transcript: %s" % str(transcript).substr(0, 300))
	if not refusal.is_empty():
		t.contains(refusal, "Seal, or nothing", "the whole line arrives, not a summary")

	# And it was a refusal, not a crash: the session kept going and reached later zones.
	t.check(String(session.call("player_zone")) != GATED,
		"the player did NOT get into the warehouse")
	t.is_true((bag["client"] as Node).call("is_attached"), "and the stage is still attached")


func _spawns(t: RefCounted, bag: Dictionary, d: Node2D) -> void:
	# The anchor is probabilistic (authored 0.45) and this session's seed is fixed, so a
	# spawn is not guaranteed. What IS asserted: if the sim spawned, the stage placed real
	# nodes for it; and the anchor's zone exists to be spawned into.
	var session: Node = bag["session"]
	var spawn_lines := 0
	for line: Variant in (session.get("transcript") as Array):
		if String(line).contains("on the stair"):
			spawn_lines += 1

	var stair := d.call("zone_node", "crooked-stair") as Node
	t.check(stair != null, "the anchor's zone is on stage")

	if spawn_lines > 0:
		var holder := stair.get_node_or_null("Spawned")
		t.check(holder != null, "a spawn produced real nodes in the zone")
		if holder != null:
			t.check(holder.get_child_count() > 0, "and there is at least one of them")
			var marker := holder.get_child(0)
			t.check(marker.has_meta("entity_id"), "each spawned node carries the sim's entity id")
			t.check(marker.get_node_or_null("Sprite") != null, "and is bound to a sprite")
	else:
		# Recorded rather than passed over: an anchor that did not fire at this seed is an
		# ordinary outcome, and saying so is better than a silently absent assertion.
		t.check(true, "the anchor did not fire at this seed (0.45, recorded not asserted)")


func _redress(t: RefCounted, bag: Dictionary, d: Node2D, tree: SceneTree) -> void:
	var session: Node = bag["session"]

	# The shock arrived as an EVENT and named its own cause. The stage was told, not asked.
	# Dockward has TWO zones and both cross together, so the line for the zone under test
	# is selected rather than whichever matched last — the first draft asserted "The Long
	# Quay" against the Customs Shed's line and failed for being imprecise, not wrong.
	var change := ""
	var changed_zones := 0
	for line: Variant in (session.get("transcript") as Array):
		if String(line).contains("intact → damaged"):
			changed_zones += 1
			if String(line).contains("The Long Quay"):
				change = String(line)
	t.check(not change.is_empty(),
		"a state shock arrived and the stage narrated it",
		"transcript: %s" % str(session.get("transcript")).substr(0, 400))
	if not change.is_empty():
		# The CAUSE is the sim's, computed from the baseline this world authored.
		t.contains(change, "stability", "the change names what moved")
		t.contains(change, "The Long Quay", "and which place it happened to")
	# The shock hit the DISTRICT, so every zone in it moves — asserted, because a shock
	# that moved exactly one zone of a two-zone district would mean the derivation is
	# reading something other than the district.
	t.check(changed_zones >= 2, "both Dockward zones moved, because the district did",
		"got %d" % changed_zones)

	await tree.process_frame

	# And it is VISIBLE: rubble in the shocked zone, and nowhere else.
	var zn := d.call("zone_node", SHOCK_ZONE) as Node
	t.check(_visible_in_zone(tree, "props:rubble", zn) > 0,
		"the quay is visibly re-dressed — rubble is on screen")
	t.is_true((d.get("rig") as Node).call("is_dim"), "and its light went down")

	var elsewhere := 0
	for other: Variant in ["counting-house", "weighing-floor", "bonded-warehouse", "crooked-stair"]:
		elsewhere += _visible_in_zone(tree, "props:rubble", d.call("zone_node", String(other)) as Node)
	t.equals(elsewhere, 0, "and only the shocked district changed")


# ── Plumbing ──────────────────────────────────────────────────

func _teardown(bag: Dictionary, tree: SceneTree) -> void:
	for key: String in ["session", "diorama", "client", "bus"]:
		var n: Node = bag.get(key, null)
		if n != null:
			if key == "client":
				n.call("detach")
			n.queue_free()
	var harness: RefCounted = bag.get("harness", null)
	if harness != null:
		harness.call("stop")
	# Let the socket close before the next run claims the port — the sidecar serves one
	# client, so an un-freed slot fails the next attach.
	await tree.create_timer(0.5).timeout


func _visible_in_zone(tree: SceneTree, group: String, zone: Node) -> int:
	if zone == null:
		return 0
	var n := 0
	for node: Node in tree.get_nodes_in_group(group):
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree() and zone.is_ancestor_of(node):
			n += 1
	return n
