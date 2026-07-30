## session.gd — the diorama, driven by the simulation.
##
## P3 put a place on screen and set its state by hand. This is the same place with the
## hand taken off: the stage submits intents, the sim decides, and everything visible
## changes because an event said so.
##
## WHAT IT DOES, AND THE ORDER MATTERS. Events arrive as a tick; the tick queue drains
## them ONE AT A TIME so a door opening, a guard turning and a refusal being spoken do
## not all happen in the same frame. Each handler translates one event into one visible
## change, and returns whatever it wants waited on.
##
## WHAT IT REFUSES TO DO, still and always:
##
##   * it never decides a move is illegal — it submits and renders the answer
##   * it never advances a tick
##   * it never corrects the sim; on a hash mismatch it says so and stops trusting itself
##
## The `move` path is the clearest case. A gated door is right there in the scene
## metadata and the stage could read it and grey out the entrance. It does not. It walks
## the player into the door and renders the reason the sim gives back, which is a person's
## refusal and belongs to the player, not to the renderer.
extends Node

const TickQueue := preload("res://client/tick_queue.gd")
const SpriteBinder := preload("res://stage/sprite_binder.gd")
const FloorPainter := preload("res://stage/floor_painter.gd")

## Events this session knows how to show. Anything else is IGNORED, not an error —
## tolerant out (RFC 9413): the sim may learn to say things this stage does not render
## yet, and a client that failed on an unknown event type would make adding one breaking.
## ⚠ MEASURED NAMES, not guessed ones. The first draft listed `gate.refused` and read
## `entityIds` off the spawn payload; the engine emits `world.zone.gate.refused` and
## `spawnedEntityIds`. Both assumptions failed silently in the useful direction — the
## events simply were not rendered — which is why the test asserts the SENTENCE reaches
## the transcript rather than that a handler was called.
const RENDERED := [
	"world.zone.entered",
	"world.zone.state.changed",
	"world.zone.gate.refused",
	"action.rejected",
	"encounter.spawned",
]

signal narrated(line: String)
signal refused(reason: String)
signal zone_entered(zone_id: String)
signal spawned(zone_id: String, entity_ids: Array)

var diorama: Node2D
var client: Node
var bus: Node
var queue: RefCounted

## Everything the stage SHOWED THE PLAYER, in presentation order.
##
## ⚠ ONLY presenter output goes here, and that separation is load-bearing. A first version
## also logged transport and staleness notices into this list — and those arrive from the
## client's `_process` via the bus, while presentation lines arrive from the tick queue's
## drain. The two interleave on frame timing, so the transcript's ORDER was not
## deterministic: the same seeded session produced the same lines in a different sequence
## on a Linux runner than on Windows, and the determinism assertion failed for a reason
## that had nothing to do with the simulation.
##
## The transcript is what a player saw. Plumbing goes in `diagnostics`.
var transcript: Array[String] = []

## Out-of-band notices — transport faults, staleness reports, connection refusals. Real
## information, deliberately not part of the replay comparison because it is timing-ordered
## rather than event-ordered.
var diagnostics: Array[String] = []

var _player_zone := ""


func setup(diorama_node: Node2D, network_client: Node, event_bus: Node) -> void:
	diorama = diorama_node
	client = network_client
	bus = event_bus

	queue = TickQueue.new()
	queue.set("presenter", Callable(self, "_present"))

	bus.tick_received.connect(_on_tick)
	bus.staleness_detected.connect(_on_staleness)
	bus.refused.connect(func(reason: String) -> void: _note("sim refused the connection: %s" % reason))
	bus.transport_failed.connect(func(detail: String) -> void: _note("transport: %s" % detail))

	_player_zone = diorama.PLAYER_START_ZONE


func player_zone() -> String:
	return _player_zone


## Walk the player toward a zone, and render whatever comes back.
##
## Deliberately does NOT check whether the move is allowed. That check exists — the gate
## is compiled into engine rules and its reason is authored — and it belongs to the sim.
func walk_to(zone_id: String) -> Dictionary:
	_face_toward(zone_id)
	var result: Dictionary = await client.call("submit_action", "move", {"targetIds": [zone_id]})
	if result.get("__error__", false):
		# A wire fault, not a refusal. Distinguished because they mean different things:
		# one is a bug, the other is the game working.
		_log("wire error on move: %s" % result.get("message", ""))
		return result
	queue.call("enqueue", result.get("events", []))
	await queue.call("drain")
	return result


## Advance the world a round without acting — the path a state shock arrives on, since
## `runZoneStateStep` runs from the world tick rather than from a verb.
func advance() -> Dictionary:
	var result: Dictionary = await client.call("request", "advance", {"rounds": 1})
	if result.get("__error__", false):
		_log("wire error on advance: %s" % result.get("message", ""))
		return result
	queue.call("enqueue", result.get("events", []))
	await queue.call("drain")
	return result


# ── Presentation ──────────────────────────────────────────────

## Turn ONE event into ONE visible change.
##
## Returns null (continue immediately) or something to await. Handlers are deliberately
## small: an event whose presentation needs a paragraph of logic is usually an event the
## sim should have been clearer about.
func _present(event: Dictionary) -> Variant:
	var type := String(event.get("type", ""))
	if not RENDERED.has(type):
		return null

	var payload: Dictionary = event.get("payload", {}) as Dictionary

	match type:
		"world.zone.entered":
			return _present_entered(payload)
		"world.zone.state.changed":
			return _present_state_changed(payload)
		"world.zone.gate.refused":
			return _present_rejected(payload)
		"action.rejected":
			return _present_rejected(payload)
		"encounter.spawned":
			return _present_spawned(payload)
	return null


func _present_entered(payload: Dictionary) -> Variant:
	var zone_id := String(payload.get("zoneId", payload.get("toZoneId", "")))
	if zone_id.is_empty():
		return null
	var came_from := _player_zone
	_player_zone = zone_id

	# Move the player's node into the zone it is now in, so the scene agrees with the sim
	# about where the player is. This is the join from P0 doing its actual job.
	var zn := diorama.call("zone_node", zone_id) as Node2D
	var player: Node2D = diorama.get("player")
	if zn != null and player != null and player.get_parent() != zn:
		player.get_parent().remove_child(player)
		zn.add_child(player)
		# Enter on the edge FACING the zone you came from, so a walk reads as
		# continuous instead of teleporting to a fixed spot. Falls back to the old
		# fixed point when there is no previous zone to face (the opening snapshot).
		player.position = _entry_point(zn, came_from)

	# The zone's authored prose, shown on arrival. This is where the Director-frozen
	# writing actually reaches a player.
	var prose := String(diorama.call("description_of", zone_id))
	if not prose.is_empty():
		_log(prose)

	# And the zone's own descriptor drives the light, so walking indoors looks like it.
	diorama.call("apply_zone_state", zone_id, [])
	zone_entered.emit(zone_id)
	return null


func _present_state_changed(payload: Dictionary) -> Variant:
	var zone_id := String(payload.get("zoneId", ""))
	var tags: Array = payload.get("variantTags", [])
	var from := String(payload.get("from", ""))
	var to := String(payload.get("to", ""))
	var cause := String(payload.get("cause", ""))

	# THE MOAT BRIDGE: five cycles of invisible economic simulation becoming a visible
	# change to a place. The stage does not decide that the quay is damaged — it is told,
	# with a cause, and it re-dresses.
	diorama.call("apply_zone_state", zone_id, tags)
	_log("%s: %s → %s (%s)" % [
		String(payload.get("zoneName", zone_id)), from, to, cause,
	])
	return null


func _present_rejected(payload: Dictionary) -> Variant:
	var reason := String(payload.get("reason", ""))
	if reason.is_empty():
		return null
	# A person's refusal, rendered as a person's refusal. Not a status code, not a greyed
	# out door — the sentence Halle actually says.
	_log(reason)
	refused.emit(reason)
	return null


func _present_spawned(payload: Dictionary) -> Variant:
	var zone_id := String(payload.get("zoneId", ""))
	var ids: Array = payload.get("spawnedEntityIds", payload.get("entityIds", []))
	var zn := diorama.call("zone_node", zone_id) as Node2D
	if zn == null:
		return null

	# Spawned entities are real nodes, placed where the sim said, so the scene population
	# tracks the simulation's rather than being decorative.
	var holder := zn.get_node_or_null("Spawned")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Spawned"
		zn.add_child(holder)

	for i in range(ids.size()):
		var marker := Node2D.new()
		marker.name = "Spawn_%s" % String(ids[i])
		marker.position = Vector2(150 + i * 40, 150)
		marker.set_meta("entity_id", String(ids[i]))
		holder.add_child(marker)
		SpriteBinder.attach(marker, "collector", diorama.CHARACTER_SCALE)

	_log("someone is on the stair (%d)" % ids.size())
	spawned.emit(zone_id, ids)
	return null


# ── Wire ──────────────────────────────────────────────────────

func _on_tick(_tick: int, _hash: String, events: Array, _delta: Array) -> void:
	# Tick notifications arrive alongside the submitAction response that caused them. The
	# queue dedups nothing — the SERVER already does, by event id — so enqueuing both
	# would double-present. Notifications are recorded and the response drives
	# presentation, which keeps one code path in charge of what the player sees.
	if events.is_empty():
		return


func _on_staleness(detail: String) -> void:
	# Reported, never corrected (charter §3.3). A stage that "fixed" a mismatch would be
	# inventing a world. Recorded as a DIAGNOSTIC rather than in the transcript: it is not
	# something the player saw, and its arrival is frame-timed.
	_note("[stale] %s" % detail)


func _log(line: String) -> void:
	transcript.append(line)
	narrated.emit(line)


## An out-of-band notice. Surfaced to a player-facing log if a UI wants it, but never part
## of the transcript the replay comparison uses.
func _note(line: String) -> void:
	diagnostics.append(line)
	narrated.emit(line)


## Where the player lands in a newly-entered zone: just inside the edge nearest the
## zone they came from. Zone-local; mirrors free_move's door-mat geometry so walking
## out of one door puts you beside the matching door on the other side.
func _entry_point(zn: Node2D, came_from: String) -> Vector2:
	var fallback := Vector2(112, 136)
	if came_from.is_empty():
		return fallback
	var pn := diorama.call("zone_node", came_from) as Node2D
	if pn == null:
		return fallback
	var p_extent: Vector2 = FloorPainter.zone_extent(pn)
	if p_extent == Vector2.ZERO:
		p_extent = Vector2(320, 224)
	var extent: Vector2 = FloorPainter.zone_extent(zn)
	if extent == Vector2.ZERO:
		extent = Vector2(320, 224)
	var margin := 26.0
	var local := zn.to_local(pn.position + p_extent * 0.5)
	return local.clamp(Vector2(margin, margin), extent - Vector2(margin, margin))


## Point the player the way they are about to walk, from the zones' own positions.
##
## Facing is presentation and derived here; the sim neither sends one nor should.
func _face_toward(zone_id: String) -> void:
	var player: Node2D = diorama.get("player")
	if player == null:
		return
	var sprite := player.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var from := diorama.call("zone_node", _player_zone) as Node2D
	var to := diorama.call("zone_node", zone_id) as Node2D
	if from == null or to == null:
		return
	SpriteBinder.face(sprite, to.position - from.position)
