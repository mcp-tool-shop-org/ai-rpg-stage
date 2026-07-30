## free_move.gd — the sprite walks.
##
## This is the layer that should never have been missing: continuous 8-way movement
## inside the zone the player is standing in. It exists entirely on the client because
## the charter puts it there — Pillar 2: the CLIENT owns coordinates, collision and
## movement feel; the SIM owns access. Nothing in this file asks permission to move
## inside a zone, and nothing in this file decides whether a zone boundary may be
## crossed. Walking is presentation; doors are rules.
##
## THE SPLIT, concretely:
##
##   * WASD / arrows move the player node inside the current zone, clamped to the
##     zone's own floor rectangle (the extent the export ships in its collision shape).
##     No wire traffic. Works with no sim attached at all — the sandbox case.
##   * Each neighbouring zone gets a DOOR MAT on the edge nearest to it. Stepping onto
##     a mat submits the real `move` intent through the session and renders whatever
##     comes back. A refusal (Halle) knocks the player a step back off the mat and the
##     door cools down, so a person hears the sentence instead of a machine-gun of it.
##
## Facing is derived from velocity through the existing sprite binder — the code that
## was built for exactly this and, until this file, was only ever fed the direction of
## a menu teleport. The walk bob is distance-driven, not clock-driven, so two identical
## input sequences look identical; the studio's determinism rule applies to gait too.
##
## The per-frame work lives in `step()` (pure: delta + an input vector in, movement
## out) so a headless test drives it directly. `_process` is one line of input
## plumbing over it.
extends Node

const SpriteBinder := preload("res://stage/sprite_binder.gd")
const FloorPainter := preload("res://stage/floor_painter.gd")

const SPEED := 150.0            ## px/s, zone-local — a person crosses a room in ~2s
const EDGE_MARGIN := 14.0       ## the feet stay this far inside the floor
## The TOP edge needs its own inset, and the reason is the pack's pivot. Sprites are
## bottom-centre: the feet sit on the node and the body extends UPWARD ~64px at this
## scale. Clamping the top to `EDGE_MARGIN` puts the feet legally inside the room while
## the whole torso hangs over the wall — which looks exactly like a clipping bug and was
## visible in the first walked render. Measured against the sprite, not guessed.
const TOP_MARGIN := 58.0
const DOOR_RADIUS := 24.0       ## stepping this close to a mat crosses / knocks
const DOOR_COOLDOWN := 0.9      ## s before the same door can fire again
const BOB_PX := 2.5             ## gait amplitude; stills glide — this keeps them alive
const BOB_WAVELENGTH := 42.0    ## px of travel per bob cycle
const KNOCKBACK_PX := 34.0
const FALLBACK_EXTENT := Vector2(320, 224)

var diorama: Node2D
## Nullable ON PURPOSE: with no session the sandbox still walks; only doors need a sim.
var session: Node
## Where door hints and sandbox notices go. Wired to the playable layer's log.
var narrate: Callable = Callable()

var _facing := "front"
var _walked := 0.0
var _crossing := false
var _doors: Array[Dictionary] = []
var _doors_zone := ""
var _cooldowns: Dictionary = {}
var _sandbox_hinted := false


func setup(diorama_node: Node2D, wire_session: Node) -> void:
	diorama = diorama_node
	session = wire_session
	# A session change is a state change: cooldowns from sandbox wandering must not
	# swallow the first real crossing, and the mats re-draw at attached brightness.
	_cooldowns.clear()
	_crossing = false
	_doors_zone = ""


func _process(delta: float) -> void:
	step(delta, _input_vector())


## One frame of movement. Public and pure-ish so headless tests drive it with
## synthetic input instead of faking keyboard events.
func step(delta: float, input_vec: Vector2) -> void:
	_tick_cooldowns(delta)
	if _crossing or diorama == null:
		return
	var player: Node2D = diorama.get("player")
	if player == null:
		return
	var zn := player.get_parent() as Node2D
	if zn == null:
		return

	_ensure_doors(zn)

	var sprite := player.get_node_or_null("Sprite") as Sprite2D
	if input_vec.is_zero_approx():
		if sprite != null:
			sprite.position.y = 0.0
		return

	var motion := input_vec.normalized() * SPEED * delta
	player.position = _clamped(player.position + motion, _extent_of(zn))
	_walked += motion.length()

	if sprite != null:
		var want := SpriteBinder.direction_for(input_vec)
		if want != _facing:
			_facing = SpriteBinder.face(sprite, input_vec)
		# The gait: distance-phased so the same walk is the same bob, every run.
		sprite.position.y = -absf(sin(_walked / BOB_WAVELENGTH * TAU)) * BOB_PX

	_check_doors(player)


# ── Doors ─────────────────────────────────────────────────────

## (Re)build the door mats when the player's zone changes. A mat is a visible thing —
## the door list stops being a menu and becomes geography.
func _ensure_doors(zn: Node2D) -> void:
	var zone_id := String(zn.get_meta("zone_id", ""))
	if zone_id.is_empty() or zone_id == _doors_zone:
		return
	_doors_zone = zone_id
	_doors.clear()
	_cooldowns.clear()

	var old := zn.get_node_or_null("Doors")
	if old != null:
		old.free()
	var holder := Node2D.new()
	holder.name = "Doors"
	zn.add_child(holder)

	var extent := _extent_of(zn)
	for neighbor: String in _neighbors_of(zone_id):
		var nn := diorama.call("zone_node", neighbor) as Node2D
		if nn == null:
			continue
		var target_center: Vector2 = nn.position + _extent_of(nn) * 0.5
		var point := _edge_point_toward(zn.to_local(target_center), extent)
		_doors.append({"id": neighbor, "point": point})
		_draw_mat(holder, point, _zone_name(neighbor))


## The point on this zone's floor edge nearest to a target (zone-local coordinates):
## clamp the target into the shrunk floor rect, then push the clamped point out to the
## rect's nearest edge so a mat always sits ON a boundary, never in the middle.
static func _edge_point_toward(local_target: Vector2, extent: Vector2) -> Vector2:
	# Mats share the walkable inset — a mat the player cannot legally stand on is a door
	# that never opens.
	var lo := Vector2(EDGE_MARGIN, TOP_MARGIN)
	var hi := extent - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var p := local_target.clamp(lo, hi)
	var d_left := absf(p.x - lo.x)
	var d_right := absf(hi.x - p.x)
	var d_top := absf(p.y - lo.y)
	var d_bottom := absf(hi.y - p.y)
	var m := minf(minf(d_left, d_right), minf(d_top, d_bottom))
	if m == d_left:
		p.x = lo.x
	elif m == d_right:
		p.x = hi.x
	elif m == d_top:
		p.y = lo.y
	else:
		p.y = hi.y
	return p


func _draw_mat(holder: Node2D, point: Vector2, label_text: String) -> void:
	var mat := Polygon2D.new()
	mat.name = "Mat"
	var w := 30.0
	var h := 10.0
	mat.polygon = PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5),
		Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5),
	])
	# Dimmer when no sim is attached: the doors are visible but honest about being inert.
	mat.color = Color(0.88, 0.72, 0.42, 0.6 if session != null else 0.25)
	mat.position = point
	holder.add_child(mat)

	var tag := Label.new()
	tag.text = label_text
	tag.add_theme_font_size_override("font_size", 9)
	tag.modulate = Color(1, 1, 1, 0.5)
	tag.position = point + Vector2(-w * 0.5, 7.0)
	holder.add_child(tag)


func _check_doors(player: Node2D) -> void:
	for door: Dictionary in _doors:
		var id := String(door["id"])
		if float(_cooldowns.get(id, 0.0)) > 0.0:
			continue
		if player.position.distance_to(door["point"] as Vector2) > DOOR_RADIUS:
			continue
		_cross(door, player)
		return


func _cross(door: Dictionary, player: Node2D) -> void:
	var id := String(door["id"])
	if session == null:
		# Sandbox: the walk works, the world doesn't decide. Said once, not per step.
		_cooldowns[id] = DOOR_COOLDOWN
		if not _sandbox_hinted and narrate.is_valid():
			_sandbox_hinted = true
			narrate.call("[i]The door needs someone to decide. Start the sim: [b]node tools/play.mjs[/b][/i]")
		return

	_crossing = true
	var before := String(session.call("player_zone"))
	await session.call("walk_to", id)
	if String(session.call("player_zone")) == before:
		# Refused — a person said no, or the wire faulted. Either way the player steps
		# back off the mat and the door rests, so the sentence lands once.
		var away := (player.position - (door["point"] as Vector2))
		away = Vector2(0, -1) if away.is_zero_approx() else away.normalized()
		player.position = _clamped(
			player.position + away * KNOCKBACK_PX,
			_extent_of(player.get_parent() as Node2D),
		)
		_cooldowns[id] = DOOR_COOLDOWN
	_crossing = false


# ── Small helpers ─────────────────────────────────────────────

func _tick_cooldowns(delta: float) -> void:
	for k: Variant in _cooldowns.keys():
		_cooldowns[k] = maxf(0.0, float(_cooldowns[k]) - delta)


static func _clamped(pos: Vector2, extent: Vector2) -> Vector2:
	return pos.clamp(
		Vector2(EDGE_MARGIN, TOP_MARGIN),
		extent - Vector2(EDGE_MARGIN, EDGE_MARGIN),
	)


static func _extent_of(zn: Node2D) -> Vector2:
	var e: Vector2 = FloorPainter.zone_extent(zn)
	return FALLBACK_EXTENT if e == Vector2.ZERO else e


func _neighbors_of(zone_id: String) -> Array[String]:
	var out: Array[String] = []
	var pack: Dictionary = diorama.get("pack")
	for z: Variant in (pack.get("zones", []) as Array):
		var zd: Dictionary = z as Dictionary
		if String(zd.get("id", "")) == zone_id:
			for n: Variant in (zd.get("neighbors", []) as Array):
				out.append(String(n))
	return out


func _zone_name(zone_id: String) -> String:
	var pack: Dictionary = diorama.get("pack")
	for z: Variant in (pack.get("zones", []) as Array):
		var zd: Dictionary = z as Dictionary
		if String(zd.get("id", "")) == zone_id:
			return String(zd.get("name", zone_id))
	return zone_id


## Keyboard → a direction. Arrows via the built-in actions, WASD polled physically so
## the project needs no InputMap edits to stay playable out of the box.
func _input_vector() -> Vector2:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	return v.limit_length(1.0)
