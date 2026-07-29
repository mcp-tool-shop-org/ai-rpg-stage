## test_scene_join.gd — P0's exit gate: the .tscn↔wire join, proven BOTH directions.
##
## The claim under test is the one every later phase rests on: when the simulation
## says something happened in `zone-under-vault`, the stage can find the node that
## is `zone-under-vault` — and knows when it cannot.
##
## Both directions, and a RED control:
##
##   forward   every zone the wire carries has a zone node on stage
##   reverse   every zone node on stage is a zone the wire carries
##   RED       a scene with ONE altered zone id FAILS, and fails by naming the
##             altered id in one direction and the real id in the other
##
## Without the RED control this file would prove only that two lists happened to
## match today. A gate that has only ever passed proves nothing.
extends RefCounted

const SceneJoin := preload("res://client/scene_join.gd")

const PACK_PATH := "res://fixtures/pack.json"
const SCENE_PATH := "res://fixtures/world.tscn"
const DOCTORED_PATH := "res://fixtures/world.doctored.tscn"

## The generator alters exactly this zone in the doctored scene.
const DOCTORED_ZONE := "zone-sky-gantry"
const DOCTORED_SUFFIX := "-DOCTORED"


func run(t: RefCounted) -> void:
	# ── The wire side ────────────────────────────────────────
	var pack := _read_json(PACK_PATH)
	if pack.is_empty():
		t.check(false, "fixture pack loads", "%s missing or not an object" % PACK_PATH)
		return

	var wire_ids: Array = pack.get("zoneIds", [])
	t.check(wire_ids.size() > 0, "wire carries at least one zone id")

	# The fixture asserting its own purpose. If this key ever flips, a later phase
	# might read gate text as authority, which is the contract violation this
	# repo exists not to commit.
	t.equals(pack.get("gatesAreInformational", null), true,
		"fixture declares its gate text informational")

	# ── The scene side ───────────────────────────────────────
	var scene := _instantiate(SCENE_PATH)
	if scene == null:
		t.check(false, "fixture scene instantiates", "%s failed to load" % SCENE_PATH)
		return

	var join: RefCounted = SceneJoin.new()
	join.call("index", scene)
	var report: Dictionary = join.call("reconcile", wire_ids)

	# ── Forward and reverse ──────────────────────────────────
	t.same_set(report["scene_zone_ids"], wire_ids, "zone ids match the wire, both directions")
	t.equals((report["missing_in_scene"] as Array).size(), 0,
		"every wire zone has a scene node")
	t.equals((report["missing_in_wire"] as Array).size(), 0,
		"every scene zone node is a wire zone")
	t.equals((report["orphan_tags"] as Array).size(), 0,
		"no descendant names a zone that has no zone node")
	t.is_true(report["ok"], "join reconciles clean")

	# ── The discriminator between zones and zone-TAGGED nodes ─
	# The exporter stamps `metadata/zone_id` on props, entities, markets and
	# transitions as well as on zones. A joiner that counted every tagged node as
	# a zone would report a number that is wrong while looking correct, so the
	# distinction is asserted rather than assumed.
	var zone_count: int = (report["scene_zone_ids"] as Array).size()
	var counts: Dictionary = pack.get("counts", {})
	t.equals(zone_count, counts.get("zones", -1),
		"zone-node count equals the pack's zone count")

	var tagged_total := 0
	for id: Variant in report["scene_zone_ids"] as Array:
		tagged_total += (join.call("tagged_nodes", id as String) as Array).size()
	t.check(tagged_total > zone_count,
		"tagged descendants outnumber zones (the two are not the same set)",
		"tagged=%d zones=%d" % [tagged_total, zone_count])

	# ── Resolution is real, not incidental ───────────────────
	for id: Variant in wire_ids:
		var node: Variant = join.call("zone_node", id as String)
		t.check(node != null, "wire zone '%s' resolves to a node" % id)

	scene.free()

	# ── RED CONTROL ──────────────────────────────────────────
	# One zone id altered in the scene. The join must fail, and must fail in BOTH
	# directions at once — which is the signature of a rename, and is exactly what
	# a one-directional check would half-miss.
	var doctored := _instantiate(DOCTORED_PATH)
	if doctored == null:
		t.check(false, "doctored control scene instantiates",
			"%s missing — the control cannot run" % DOCTORED_PATH)
		return

	var red: RefCounted = SceneJoin.new()
	red.call("index", doctored)
	var red_report: Dictionary = red.call("reconcile", wire_ids)

	t.is_false(red_report["ok"], "RED: doctored scene FAILS to reconcile")
	t.contains(red_report["missing_in_scene"], DOCTORED_ZONE,
		"RED: the real zone is reported missing from the scene")
	t.contains(red_report["missing_in_wire"], DOCTORED_ZONE + DOCTORED_SUFFIX,
		"RED: the altered id is reported absent from the wire")
	# And the failure is narrow: doctoring one zone must not disturb the others.
	t.equals((red_report["missing_in_scene"] as Array).size(), 1,
		"RED: exactly one zone missing from the scene")
	t.equals((red_report["missing_in_wire"] as Array).size(), 1,
		"RED: exactly one node absent from the wire")

	doctored.free()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed: Variant = load(path)
	if not packed is PackedScene:
		return null
	return (packed as PackedScene).instantiate()
