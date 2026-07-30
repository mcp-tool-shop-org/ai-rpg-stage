## test_diorama.gd — P3's exit gate: the diorama stands up, and the re-dress is real.
##
## Headless, so nothing here can assert that the scene looks good — that is the
## Director's eye and a screenshot's job. What it CAN assert is everything that would
## make a screenshot a lie:
##
##   * the rig exists and its ambient really changes with the descriptor
##   * `lighting:dim` darkens, and the darkening is READ BACK OFF THE NODE
##   * a re-dress swaps dressing and moves NOTHING — the Triangle Strategy rule, as a test
##   * the cast is attached, with normal maps bound so the light has something to catch
##   * eight-direction bucketing is right at all eight compass points
##   * the frozen prose reaches the stage
##   * the stage has no way to adjudicate a gate
extends RefCounted

const Diorama := preload("res://stage/diorama.gd")
const SpriteBinder := preload("res://stage/sprite_binder.gd")
const LightRig := preload("res://stage/light_rig.gd")

## The zone the shock lands on: Dockward is authored fragile so it can actually move.
const SHOCK_ZONE := "long-quay"


## Sections that must all run. See `_completed` below — this is the canary.
const SECTIONS := [
	"bucketing", "assembled", "prose", "no-adjudication", "cast", "light", "redress",
]

var _completed: Array[String] = []


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "the diorama needs a tree for groups")
		return

	_direction_bucketing(t) # pure maths, no scene needed
	_completed.append("bucketing")

	var d: Node2D = Diorama.new()
	d.name = "Diorama"
	tree.root.add_child(d)

	# ⚠ AWAIT A FRAME BEFORE BUILDING, and this is a property of the harness rather than
	# of the diorama. `_initialize()` runs before the SceneTree's first iteration, so a
	# node added to `tree.root` here is NOT in the tree yet — measured directly:
	# `is_inside_tree()` returns false straight after `add_child`. Building in that state
	# makes every `get_tree()` inside the scene return null, which Godot reports as
	# `Parameter "data.tree" is null` before the null-guards absorb it. The suite passed
	# anyway, with two unexplained errors in the log, which is how a log stops being read.
	#
	# Any future test that adds nodes in `_initialize` needs this same frame.
	await tree.process_frame

	# `build()` explicitly rather than relying on `_ready` — which has already run and
	# returned early, since `build()` is idempotent.
	d.call("build")
	await tree.process_frame

	_assembled(t, d)
	_completed.append("assembled")
	_prose_reaches_the_stage(t, d)
	_completed.append("prose")
	_the_stage_cannot_adjudicate(t, d)
	_completed.append("no-adjudication")
	_cast_is_lit(t, d)
	_completed.append("cast")
	_light_follows_the_descriptor(t, d)
	_completed.append("light")
	# ⚠ AWAITED. This one waits on frames, so calling it bare returns at its first await
	# and everything after that line never runs — including this file's load-bearing
	# assertion that a re-dress moves NOTHING. The suite reported 43/43 PASS while the
	# most important check in it had not executed. An un-awaited coroutine truncates
	# silently, and a truncated test looks exactly like a passing one.
	await _redress_swaps_without_moving(t, d, tree)
	_completed.append("redress")

	# ⚠ THE TRUNCATION CANARY, and it is here because this file needed it. A runtime
	# error inside a section — a wrong argument count, an un-awaited coroutine — stops
	# that section and every one after it, and the runner cannot tell a section that
	# passed from one that never ran. This file reported 43/43 PASS twice while its
	# load-bearing assertion was unreachable. Now a missing section is a named failure.
	t.same_set(_completed, SECTIONS, "every section of this suite ran to completion")


	d.queue_free()


func _direction_bucketing(t: RefCounted) -> void:
	# Screen space: +y is DOWN, so moving down is `front` (toward the camera). All eight
	# compass points asserted, because an off-by-one in the bucket maths gives a
	# character that faces 45 degrees wrong — wrong in a way that looks intentional.
	var cases := {
		"front": Vector2(0, 1),
		"back": Vector2(0, -1),
		"right": Vector2(1, 0),
		"left": Vector2(-1, 0),
		"front_right": Vector2(1, 1),
		"front_left": Vector2(-1, 1),
		"back_right": Vector2(1, -1),
		"back_left": Vector2(-1, -1),
	}
	for expected: String in cases:
		t.equals(SpriteBinder.direction_for(cases[expected]), expected,
			"motion %s faces %s" % [cases[expected], expected])

	# Standing still has to be defined, not incidental.
	t.equals(SpriteBinder.direction_for(Vector2.ZERO), "front", "no motion faces front")
	# And the derivation must cover the pack's whole list — a bucket that never appears
	# would be a sprite that never renders.
	var produced := {}
	for i in range(16):
		var a := TAU * float(i) / 16.0
		produced[SpriteBinder.direction_for(Vector2(cos(a), sin(a)))] = true
	t.equals(produced.size(), SpriteBinder.DIRECTIONS.size(),
		"every one of the pack's eight directions is reachable")


func _assembled(t: RefCounted, d: Node2D) -> void:
	t.check(d.get("world") != null, "the exported world is instanced")
	t.check(d.get("rig") != null, "the light rig exists")
	t.check(d.get("dressing") != null, "the dressing system exists")
	t.check(d.get("player") != null, "the player is placed")
	t.check(d.get_node_or_null("DioramaCamera") != null, "a camera frames the scene")

	var rig: Node = d.get("rig")
	t.check(rig.get("ambient") != null, "the rig has a CanvasModulate")
	t.check(rig.get("sun") != null, "the rig has a DirectionalLight2D")

	# Every zone resolves — the join from P0, still holding against the real world.
	var pack: Dictionary = d.get("pack")
	var ids: Array = pack.get("zoneIds", [])
	t.check(ids.size() >= 6, "the diorama carries Salt Road's zones", "got %d" % ids.size())
	var resolved := 0
	for id: Variant in ids:
		if d.call("zone_node", String(id)) != null:
			resolved += 1
	t.equals(resolved, ids.size(), "every zone in the pack resolves to a node")


func _prose_reaches_the_stage(t: RefCounted, d: Node2D) -> void:
	# The Director-frozen writing is dropped at intake (`no-runtime-field`) and stamped
	# into the .tscn as `metadata/description`. If this ever fails, the prose has stopped
	# reaching the only layer that can show it.
	var counting := String(d.call("description_of", "counting-house"))
	t.check(counting.contains("wax jack"), "the counting house's prose is on the stage")
	var quay := String(d.call("description_of", SHOCK_ZONE))
	t.check(quay.contains("does not look wet"), "the quay's prose is on the stage")

	var described := 0
	for id: Variant in ((d.get("pack") as Dictionary).get("zoneIds", []) as Array):
		if not String(d.call("description_of", String(id))).is_empty():
			described += 1
	t.equals(described, 6, "all six zones carry their description")


func _the_stage_cannot_adjudicate(t: RefCounted, d: Node2D) -> void:
	# The gate's REASON is available for display — it is a person's line and the player
	# must see it. What must NOT exist is any way for the stage to decide the gate.
	var reason := String(d.call("gate_text_of", "bonded-warehouse"))
	t.check(reason.contains("mother in Dockward"), "the gate's authored reason is readable")

	# Asserted structurally: no method on the stage answers "may I enter".
	for forbidden: String in ["can_enter", "is_gate_open", "evaluate_gate", "check_gate"]:
		t.is_false(d.has_method(forbidden),
			"the diorama has no %s() — gates are the sim's to decide" % forbidden)
	var join: Variant = d.get("join")
	for forbidden: String in ["can_enter", "evaluate_gate"]:
		t.is_false((join as Object).has_method(forbidden),
			"the joiner has no %s() either" % forbidden)


func _cast_is_lit(t: RefCounted, d: Node2D) -> void:
	# A sprite bound without its normal map lights flatly, which on a painterly 512px
	# character is most of the difference between sitting IN the scene and on top of it.
	var lit := 0
	var found := 0
	for member: Dictionary in Diorama.CAST:
		var zn := d.call("zone_node", String(member["zone"])) as Node
		if zn == null:
			continue
		var holder := zn.get_node_or_null(String(member["id"]))
		if holder == null:
			continue
		found += 1
		var sprite := holder.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			continue
		var tex := sprite.texture as CanvasTexture
		if tex != null and tex.normal_texture != null:
			lit += 1

	t.equals(found, Diorama.CAST.size(), "every cast member is placed in their zone")
	t.equals(lit, Diorama.CAST.size(), "every cast member carries a normal map")

	# The player too, and the player is the one that must be able to turn.
	var player: Node = d.get("player")
	var psprite := player.get_node_or_null("Sprite") as Sprite2D
	t.check(psprite != null, "the player has a sprite")
	t.is_true(SpriteBinder.has_all_directions(Diorama.PLAYER_CHARACTER),
		"the player has all eight facings vendored")
	# And the standing cast honestly does not — asserted so a later phase does not try to
	# turn them and get a blank texture.
	t.is_false(SpriteBinder.has_all_directions("halle"),
		"a standing NPC has one facing, and the binder knows it")

	if psprite != null:
		var before := String(psprite.get_meta("facing"))
		var turned := String(SpriteBinder.face(psprite, Vector2(0, -1)))
		t.equals(turned, "back", "the player can turn to face away")
		t.not_equals(turned, before, "and turning actually changed the sprite")


func _light_follows_the_descriptor(t: RefCounted, d: Node2D) -> void:
	var rig: Node = d.get("rig")

	rig.call("apply_descriptor", {"timeOfDay": "morning"}, [])
	var morning: Color = rig.call("ambient_color")
	t.equals(String(rig.call("time_of_day")), "morning", "the rig took the authored timeOfDay")

	rig.call("apply_descriptor", {"timeOfDay": "night"}, [])
	var night: Color = rig.call("ambient_color")
	t.not_equals(night, morning, "night looks different from morning")
	t.check(night.b > night.r, "night is cool, not warm", "got %s" % night)

	# `lighting:dim` is the one lighting key the SIM derives — from condition, not clock.
	rig.call("apply_descriptor", {"timeOfDay": "morning"}, ["lighting:dim"])
	var dimmed: Color = rig.call("ambient_color")
	t.is_true(rig.call("is_dim"), "the rig registered lighting:dim")
	t.check(dimmed.r < morning.r and dimmed.g < morning.g and dimmed.b < morning.b,
		"dim really is darker than the same hour undimmed",
		"%s vs %s" % [dimmed, morning])

	# Tolerant OUT: a descriptor key the stage does not know must not break it.
	rig.call("apply_descriptor", {"timeOfDay": "a-word-the-stage-has-never-heard"}, [])
	t.equals(String(rig.call("time_of_day")), "morning",
		"an unknown timeOfDay falls back instead of failing")


func _redress_swaps_without_moving(t: RefCounted, d: Node2D, tree: SceneTree) -> void:
	var dressing: Node = d.get("dressing")
	var zn := d.call("zone_node", SHOCK_ZONE) as Node2D

	# Record the LAYOUT before the shock: every child's position, by path.
	var before: Dictionary = _positions(zn)
	t.check(before.size() > 0, "the zone has positioned children to compare")

	# Intact.
	d.call("apply_zone_state", SHOCK_ZONE, ["dressing:intact"])
	await tree.process_frame
	t.equals(_visible_in_zone(tree, "props:rubble", zn), 0, "no rubble while the quay is intact")

	# The shock: damaged.
	d.call("apply_zone_state", SHOCK_ZONE, ["dressing:damaged", "lighting:dim", "props:rubble"])
	await tree.process_frame

	t.check(_visible_in_zone(tree, "props:rubble", zn) > 0, "rubble appears when the quay is damaged")

	# ⚠ AND NOWHERE ELSE. Found by looking at the render: the first version toggled groups
	# tree-wide, so shocking the quay put rubble in all six rooms — every zone damaged
	# because one was. `world.zone.state.changed` names ONE zone and this is that, asserted.
	var elsewhere := 0
	for other: Variant in ((d.get("pack") as Dictionary).get("zoneIds", []) as Array):
		if String(other) == SHOCK_ZONE:
			continue
		elsewhere += _visible_in_zone(tree, "props:rubble", d.call("zone_node", String(other)) as Node)
	t.equals(elsewhere, 0, "the shock re-dressed ONE zone and left the other five alone")
	t.contains(dressing.call("active_tags"), "props:rubble", "the dressing system reports the swap")
	t.is_true((d.get("rig") as Node).call("is_dim"), "and the light went down with it")

	# ⚠ THE LOAD-BEARING ASSERTION. Dressing swaps; LAYOUT DOES NOT MOVE (Triangle
	# Strategy's rule, and the reason Suikoden II's Ryube lands — the player has to
	# recognise the place afterwards). A re-dress that relocated a crate would read as a
	# loading error rather than as a consequence.
	var after: Dictionary = _positions(zn)
	var moved: Array[String] = []
	for path: Variant in before.keys():
		if after.has(path) and after[path] != before[path]:
			moved.append(String(path))
	t.check(moved.is_empty(), "the re-dress moved NOTHING", "moved: %s" % str(moved))

	# Idempotence: applying the same state twice is the same state. Hide-all-then-show
	# is what buys this; toggling only deltas would leave the scene dependent on the
	# order shocks arrived in.
	var snapshot: Array = dressing.call("active_tags")
	d.call("apply_zone_state", SHOCK_ZONE, ["dressing:damaged", "lighting:dim", "props:rubble"])
	await tree.process_frame
	t.equals(dressing.call("active_tags"), snapshot, "re-applying the same state changes nothing")

	# And back: a shock is reversible, which is what makes it a state rather than an event.
	d.call("apply_zone_state", SHOCK_ZONE, ["dressing:intact"])
	await tree.process_frame
	t.equals(_visible_in_zone(tree, "props:rubble", zn), 0, "the rubble goes away again")
	t.is_false((d.get("rig") as Node).call("is_dim"), "and the light comes back up")


func _positions(root: Node) -> Dictionary:
	var out: Dictionary = {}
	_walk_positions(root, root, out)
	return out


func _walk_positions(node: Node, root: Node, out: Dictionary) -> void:
	for child: Node in node.get_children():
		if child is Node2D:
			out[String(root.get_path_to(child))] = (child as Node2D).position
		_walk_positions(child, root, out)


## Visible members of a group INSIDE one zone. Counting tree-wide is what let a
## town-wide re-dress read as a passing test.
func _visible_in_zone(tree: SceneTree, group: String, zone: Node) -> int:
	if zone == null:
		return 0
	var n := 0
	for node: Node in tree.get_nodes_in_group(group):
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree() and zone.is_ancestor_of(node):
			n += 1
	return n
