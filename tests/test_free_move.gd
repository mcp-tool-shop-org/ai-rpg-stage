## test_free_move.gd — the sprite walks, and the walking obeys the contract.
##
## Headless, so it cannot assert that walking FEELS right — that is a hands-on-keys
## judgment. What it CAN assert is every property that makes free movement honest:
##
##   * `step()` moves the player node, and input direction changes the sprite's facing
##   * the walk is CLAMPED to the zone's own floor — no escaping the rectangle
##   * every neighbour gets a door mat, placed on the zone's edge
##   * stepping onto a mat submits the move THROUGH THE SESSION — the mover never
##     relocates the player itself (access is the sim's; this file proves the client
##     only ever asks)
##   * a refusal knocks the player back off the mat and the door cools down, so the
##     next frame does not re-fire it
##   * with NO session at all, walking still works and door contact does not crash —
##     the sandbox case, which is the whole point
extends RefCounted

const Diorama := preload("res://stage/diorama.gd")
const FreeMove := preload("res://stage/free_move.gd")

const SECTIONS := [
	"moves", "clamped", "faces", "doors", "asks-the-session", "knockback",
	"no-ping-pong", "sandbox",
]

var _completed: Array[String] = []


## A session stand-in that RECORDS instead of deciding. `zone_after` is what
## `player_zone()` returns after a walk — leave it equal to the start zone to play a
## refusal, change it to play an accepted move.
##
## Extends NODE, not RefCounted: `free_move.setup()` types its session parameter as
## Node (the real session is one), and passing a RefCounted is a runtime type error —
## which does not fail loudly in a coroutine, it TRUNCATES it. The section canaries
## caught exactly that on this file's first run.
class StubSession:
	extends Node
	var walked: Array[String] = []
	var zone := "counting-house"
	var zone_after := ""

	func player_zone() -> String:
		return zone

	func walk_to(zone_id: String) -> Dictionary:
		walked.append(zone_id)
		if not zone_after.is_empty():
			zone = zone_after
		return {}


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "free_move needs a tree")
		return

	var d: Node2D = Diorama.new()
	d.name = "DioramaForFreeMove"
	tree.root.add_child(d)
	# The harness property test_diorama.gd records: nodes added in _initialize are not
	# in the tree until a frame passes, and building before then leaves get_tree() null.
	await tree.process_frame
	d.call("build")
	await tree.process_frame

	var player: Node2D = d.get("player")
	if player == null:
		t.check(false, "the diorama placed a player", "cannot test movement without one")
		d.free()
		return

	var mover: Node = FreeMove.new()
	mover.name = "FreeMove"
	tree.root.add_child(mover)
	await tree.process_frame

	var stub := StubSession.new()
	stub.name = "StubSession"
	tree.root.add_child(stub)

	_moves(t, d, mover, player)
	_clamped(t, d, mover, player)
	_faces(t, mover, player)
	_doors(t, d, player)
	await _asks_the_session(t, d, mover, player, stub)
	await _knockback(t, d, mover, player, stub)
	await _no_ping_pong(t, d, mover, player, stub)
	_sandbox(t, d, mover, player)

	for s: String in SECTIONS:
		t.check(_completed.has(s), "section ran: %s" % s, "truncated before it")

	stub.free()
	mover.free()
	d.free()


func _moves(t: RefCounted, d: Node2D, mover: Node, player: Node2D) -> void:
	mover.call("setup", d, null)
	player.position = Vector2(100, 100)
	var before := player.position
	for _i in range(30):
		mover.call("step", 1.0 / 60.0, Vector2(1, 0))
	t.check(player.position.x > before.x + 40.0, "walking right moves the player right",
		"moved %.1f px" % (player.position.x - before.x))
	t.equals(player.position.y, before.y, "a horizontal walk does not drift vertically")
	_completed.append("moves")


func _clamped(t: RefCounted, d: Node2D, mover: Node, player: Node2D) -> void:
	# Walk hard at one wall for far longer than the room is wide.
	for _i in range(600):
		mover.call("step", 1.0 / 60.0, Vector2(1, 0))
	var zn := player.get_parent() as Node2D
	var extent: Vector2 = mover.call("_extent_of", zn)
	t.check(player.position.x <= extent.x - 13.9, "the walk is clamped inside the floor",
		"x=%.1f extent=%.1f" % [player.position.x, extent.x])
	t.check(player.position.x >= extent.x - 40.0, "…and the clamp is AT the wall, not short of it",
		"x=%.1f" % player.position.x)
	_completed.append("clamped")


func _faces(t: RefCounted, mover: Node, player: Node2D) -> void:
	var sprite := player.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		t.check(false, "the player has a sprite to face")
		return
	player.position = Vector2(100, 100)
	mover.call("step", 1.0 / 60.0, Vector2(0, -1))
	t.equals(String(sprite.get_meta("facing", "")), "back", "walking up faces the sprite away")
	mover.call("step", 1.0 / 60.0, Vector2(0, 1))
	t.equals(String(sprite.get_meta("facing", "")), "front", "walking down faces the camera")
	t.check(sprite.position.y < 0.0, "mid-walk the gait bob lifts the sprite",
		"y=%.2f" % sprite.position.y)
	mover.call("step", 1.0 / 60.0, Vector2.ZERO)
	t.equals(sprite.position.y, 0.0, "standing still rests the gait")
	_completed.append("faces")


func _doors(t: RefCounted, d: Node2D, player: Node2D) -> void:
	var zn := player.get_parent() as Node2D
	var doors := zn.get_node_or_null("Doors")
	if doors == null:
		t.check(false, "a Doors container exists after stepping")
		return
	var mats := 0
	for c: Node in doors.get_children():
		if c.name == "Mat":
			mats += 1
	# Count neighbours off the fixture the same way the mover does.
	var expected := 0
	for z: Variant in ((d.get("pack") as Dictionary).get("zones", []) as Array):
		if String((z as Dictionary).get("id", "")) == String(zn.get_meta("zone_id", "")):
			expected = ((z as Dictionary).get("neighbors", []) as Array).size()
	t.check(expected > 0, "the start zone has at least one neighbour", "fixture problem otherwise")
	t.equals(mats, expected, "every neighbour got a door mat")
	_completed.append("doors")


func _asks_the_session(t: RefCounted, d: Node2D, mover: Node, player: Node2D, stub: Node) -> void:
	var zn := player.get_parent() as Node2D
	stub.set("zone", String(zn.get_meta("zone_id", "")))
	stub.set("zone_after", stub.get("zone"))  # sim says no — zone unchanged
	mover.call("setup", d, stub)

	var mats: Array[Dictionary] = mover.get("_doors")
	if mats.is_empty():
		t.check(false, "the mover knows its doors")
		return
	var door: Dictionary = mats[0]

	# Doors fire while WALKING (you cross by stepping in, not by standing about), so the
	# test walks one frame while on the mat rather than teleporting and idling.
	player.position = door["point"] as Vector2
	mover.call("step", 1.0 / 60.0, Vector2(1, 0))
	# _cross awaits the stub; give the coroutine a frame to complete.
	await (Engine.get_main_loop() as SceneTree).process_frame
	var walked: Array = stub.get("walked")
	t.equals(walked.size(), 1, "door contact submitted exactly one move")
	if walked.size() == 1:
		t.equals(String(walked[0]), String(door["id"]), "…to the zone the mat belongs to")
	t.check(player.get_parent() == zn, "the mover did NOT relocate the player itself",
		"access is the sim's decision, and the sim said no")
	_completed.append("asks-the-session")


func _knockback(t: RefCounted, d: Node2D, mover: Node, player: Node2D, stub: Node) -> void:
	var mats: Array[Dictionary] = mover.get("_doors")
	var door: Dictionary = mats[0]
	var mat_point := door["point"] as Vector2
	t.check(player.position.distance_to(mat_point) > 24.0,
		"the refusal knocked the player back off the mat",
		"%.1f px away" % player.position.distance_to(mat_point))

	# Cooldown: standing where we landed and stepping again must NOT re-submit.
	var calls_before: int = (stub.get("walked") as Array).size()
	player.position = mat_point
	mover.call("step", 1.0 / 60.0, Vector2(1, 0))
	await (Engine.get_main_loop() as SceneTree).process_frame
	t.equals((stub.get("walked") as Array).size(), calls_before,
		"the door is cooling down — no machine-gun refusals")
	_completed.append("knockback")


## THE PING-PONG, which shipped and which the Director hit within seconds: crossing a
## door landed the player ON the return threshold, so the next frame walked them back,
## and every bounce was a round trip with input ignored — a freeze followed by a glitch.
##
## Two properties, because either alone still bounces:
##   1. an ACCEPTED crossing rests the door back the way you came
##   2. those cooldowns survive the zone change that follows
func _no_ping_pong(t: RefCounted, d: Node2D, mover: Node, player: Node2D, stub: Node) -> void:
	var zn := player.get_parent() as Node2D
	var here := String(zn.get_meta("zone_id", ""))
	var mats: Array[Dictionary] = mover.get("_doors")
	if mats.is_empty():
		t.check(false, "the mover knows its doors")
		return
	var there := String(mats[0]["id"])

	# Play an ACCEPTED move this time: the stub reports the new zone.
	stub.set("zone", here)
	stub.set("zone_after", there)
	mover.call("setup", d, stub)  # clears cooldowns, as a fresh attach should
	var walked_before: int = (stub.get("walked") as Array).size()

	player.position = mats[0]["point"] as Vector2
	mover.call("step", 1.0 / 60.0, Vector2(1, 0))
	await (Engine.get_main_loop() as SceneTree).process_frame
	t.equals((stub.get("walked") as Array).size(), walked_before + 1,
		"the accepted crossing submitted its move")

	var cooldowns: Dictionary = mover.get("_cooldowns")
	t.check(float(cooldowns.get(here, 0.0)) > 0.0,
		"the door BACK the way we came is resting after an accepted crossing",
		"a live return door is half the ping-pong")

	# And the rebuild that follows a zone change must not wipe it.
	mover.call("_ensure_doors", zn)
	var after: Dictionary = mover.get("_cooldowns")
	t.check(float(after.get(here, 0.0)) > 0.0,
		"…and rebuilding the doors does NOT clear it",
		"clearing on zone change was the other half")
	_completed.append("no-ping-pong")


func _sandbox(t: RefCounted, d: Node2D, mover: Node, player: Node2D) -> void:
	mover.call("setup", d, null)
	player.position = Vector2(60, 60)
	var before := player.position
	for _i in range(10):
		mover.call("step", 1.0 / 60.0, Vector2(1, 1))
	t.check(player.position.distance_to(before) > 10.0, "with no session the walk still works")
	var mats: Array[Dictionary] = mover.get("_doors")
	if not mats.is_empty():
		player.position = mats[0]["point"] as Vector2
		mover.call("step", 1.0 / 60.0, Vector2.ZERO)
		t.check(true, "door contact with no session does not crash")
	_completed.append("sandbox")
