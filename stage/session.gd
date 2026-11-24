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
##   * it never patches the sim; on a digest mismatch it logs the offset, resyncs its mirror
##     from an authoritative snapshot (capped at 3 in a row), and halts play if the cap trips
##
## The `move` path is the clearest case. A gated door is right there in the scene
## metadata and the stage could read it and grey out the entrance. It does not. It walks
## the player into the door and renders the reason the sim gives back, which is a person's
## refusal and belongs to the player, not to the renderer.
extends Node

const TickQueue := preload("res://client/tick_queue.gd")
const SpriteBinder := preload("res://stage/sprite_binder.gd")
const FeltMixer := preload("res://stage/felt_mixer.gd")
const FeltJuice := preload("res://stage/felt_juice.gd")
const FeltVoice := preload("res://stage/felt_voice.gd")

## Events with bespoke scene/transcript handlers. Any event type outside `RENDERED`
## renders one deterministic fallback transcript line in `FALLBACK_COLOR` naming
## its `type` and sorted `payload` keys (tolerant out, RFC 9413: unknown types are
## made visible without failing the session).
## ⚠ MEASURED NAMES, not guessed ones. The first draft listed `gate.refused` and read
## `entityIds` off the spawn payload; the engine emits `world.zone.gate.refused` and
## `spawnedEntityIds`. Both assumptions failed quietly until asserted against the real
## event stream — which is why tests assert that sentences reach `transcript`.
const RENDERED := [
	"world.zone.entered",
	"world.zone.state.changed",
	"world.zone.gate.refused",
	"action.rejected",
	"encounter.spawned",
]

## Distinct presentation style shared by fallback event lines and surfaced warnings.
const FALLBACK_COLOR := "#8a9ba8"
const FALLBACK_TAG := "[fallback]"

signal narrated(line: String)
signal refused(reason: String)
signal zone_entered(zone_id: String)
signal spawned(zone_id: String, entity_ids: Array)

var diorama: Node2D
var client: Node
var bus: Node
var queue: RefCounted
var mixer: Node
var juice: Node
var voice: Node

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
var _halted := false
var _halt_reason := ""
var _seen_sidecar_warnings: Dictionary = {}


func setup(diorama_node: Node2D, network_client: Node, event_bus: Node) -> void:
	diorama = diorama_node
	client = network_client
	bus = event_bus

	queue = TickQueue.new()
	queue.set("presenter", Callable(self, "_present"))

	mixer = FeltMixer.new()
	mixer.name = "FeltMixer"
	add_child(mixer)
	juice = FeltJuice.new()
	juice.name = "FeltJuice"
	add_child(juice)
	voice = FeltVoice.new()
	voice.name = "FeltVoice"
	add_child(voice)

	bus.tick_received.connect(_on_tick)
	bus.staleness_detected.connect(_on_staleness)
	bus.session_halted.connect(_on_session_halted)
	bus.refused.connect(func(reason: String) -> void: _note("sim refused the connection: %s" % reason))
	bus.transport_failed.connect(func(detail: String) -> void: _note("transport: %s" % detail))

	_player_zone = diorama.PLAYER_START_ZONE


func player_zone() -> String:
	return _player_zone


func is_halted() -> bool:
	return _halted


func is_syncing() -> bool:
	return client != null and not _halted and not bool(client.call("has_baseline"))


func is_synced() -> bool:
	return client != null and bool(client.call("has_baseline"))


func halt_reason() -> String:
	return _halt_reason


## Walk the player toward a zone, and render whatever comes back.
##
## Deliberately does NOT check whether the move is allowed. That check exists — the gate
## is compiled into engine rules and its reason is authored — and it belongs to the sim.
func walk_to(zone_id: String) -> Dictionary:
	if _halted:
		return {"__error__": true, "code": -32099, "message": _halt_reason}
	if is_syncing():
		_note("syncing: waiting for baseline snapshot before play input")
		return {"__error__": true, "code": -32098, "message": "syncing: waiting for baseline snapshot before play input"}
	_face_toward(zone_id)
	var result: Dictionary = await client.call("submit_action", "move", {"targetIds": [zone_id]})
	if result.get("__error__", false):
		# A wire fault, not a refusal. Distinguished because they mean different things:
		# one is a bug, the other is the game working.
		_log("wire error on move: %s" % result.get("message", ""))
		return result
	_apply_felt(result)
	queue.call("enqueue", result.get("events", []))
	await queue.call("drain")
	return result


## Advance the world a round without acting — the path a state shock arrives on, since
## `runZoneStateStep` runs from the world tick rather than from a verb.
func advance() -> Dictionary:
	if _halted:
		return {"__error__": true, "code": -32099, "message": _halt_reason}
	if is_syncing():
		_note("syncing: waiting for baseline snapshot before play input")
		return {"__error__": true, "code": -32098, "message": "syncing: waiting for baseline snapshot before play input"}
	var result: Dictionary = await client.call("advance", 1)
	if result.get("__error__", false):
		_log("wire error on advance: %s" % result.get("message", ""))
		return result
	_apply_felt(result)
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
	var raw_payload: Variant = event.get("payload", {})
	var payload: Dictionary = raw_payload as Dictionary if raw_payload is Dictionary else {}
	if not RENDERED.has(type):
		return _present_fallback(type, payload)

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


func _present_fallback(type: String, payload: Dictionary) -> Variant:
	var keys: Array[String] = []
	for k: Variant in payload.keys():
		keys.append(String(k))
	keys.sort()
	_log(format_fallback_line(type, ", ".join(keys)))
	return null


func _present_entered(payload: Dictionary) -> Variant:
	var zone_id := String(payload.get("zoneId", payload.get("toZoneId", "")))
	if zone_id.is_empty():
		return null
	_player_zone = zone_id

	# Move the player's node into the zone it is now in, so the scene agrees with the sim
	# about where the player is. This is the join from P0 doing its actual job.
	var zn := diorama.call("zone_node", zone_id) as Node2D
	var player: Node2D = diorama.get("player")
	if zn != null and player != null and player.get_parent() != zn:
		player.get_parent().remove_child(player)
		zn.add_child(player)
		player.position = Vector2(112, 136)

	# The zone's authored prose, shown on arrival. This is where the Director-frozen
	# writing actually reaches a player.
	var prose := String(diorama.call("description_of", zone_id))
	if not prose.is_empty():
		_log(prose)

	# And the zone's own descriptor drives the light, so walking indoors looks like it.
	diorama.call("apply_zone_state", zone_id, [])
	diorama.call("look_at_zone", zone_id)
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
	var iso: Node = diorama.get("iso") if diorama else null
	if iso and iso.has_method("face_only"):
		iso.call("face_only", Vector2.DOWN)
	return null


func _present_spawned(payload: Dictionary) -> Variant:
	var zone_id := String(payload.get("zoneId", ""))
	var ids: Array = payload.get("spawnedEntityIds", payload.get("entityIds", []))
	var iso: Node = diorama.get("iso") if diorama else null
	if iso and iso.has_method("spawn_entity"):
		for i in range(ids.size()):
			iso.call("spawn_entity", zone_id, String(ids[i]), i)
		_log("someone is on the stair (%d)" % ids.size())
		spawned.emit(zone_id, ids)
		return null

	# Hidden fourth-wall world: keep a marker so older join tests can still see a node.
	var zn := diorama.call("zone_node", zone_id) as Node2D
	if zn == null:
		return null
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

func _apply_felt(result: Dictionary) -> void:
	# One beat per committed turn, from the RPC result — not from the tick
	# notification, which would double-play the same commands.
	var felt: Dictionary = result.get("felt", {}) as Dictionary
	if felt.is_empty():
		return
	if mixer:
		mixer.call("execute", felt.get("audio", []))
	if juice and diorama:
		juice.call("apply", felt.get("uiEffects", []), diorama.call("camera"))
	var speaker: Variant = felt.get("speaker", {})
	if speaker is Dictionary and not (speaker as Dictionary).is_empty() and voice:
		voice.call("speak", speaker)


func _on_tick(_tick: int, _hash: String, events: Array, _delta: Array) -> void:
	# Tick notifications arrive alongside the submitAction response that caused them. The
	# queue dedups nothing — the SERVER already does, by event id — so enqueuing both
	# would double-present. Notifications are recorded and the response drives
	# presentation, which keeps one code path in charge of what the player sees.
	# Felt rides the same rule: play from the response, ignore the tick copy.
	if events.is_empty():
		return


func _on_staleness(detail: String) -> void:
	# Mirror or position diverged: logged with pre-image offset and resynced from the
	# engine's authoritative snapshot rather than patching the sim. Recorded as a
	# DIAGNOSTIC so frame timing never perturbs replay-transcript ordering.
	_note("[stale] %s" % detail)


func _on_session_halted(reason: String) -> void:
	_halted = true
	_halt_reason = reason
	_note("[halt] %s" % reason)
	_log("[color=#c66]Sync halted: %s[/color]" % reason)


## Format a line in the distinct fallback transcript style.
static func format_fallback_line(label: String, keys_or_detail: String = "") -> String:
	if keys_or_detail.is_empty():
		return "[color=%s]%s %s[/color]" % [FALLBACK_COLOR, FALLBACK_TAG, label]
	return "[color=%s]%s %s (%s)[/color]" % [FALLBACK_COLOR, FALLBACK_TAG, label, keys_or_detail]


## Surface sidecar stderr warning lines (e.g. from `--unresolved-ai-profile warn`) to both
## the diagnostic log and on-screen transcript in the fallback style.
func ingest_sidecar_stderr(stderr_text: String) -> int:
	var surfaced := 0
	for raw: String in stderr_text.split("\n", false):
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		if not (line.contains("[sidecar] warning") or line.contains("UNRESOLVED_AI_PROFILE")):
			continue
		var key := _warning_dedup_key(line)
		if _seen_sidecar_warnings.has(key):
			continue
		_seen_sidecar_warnings[key] = true
		diagnostics.append("[warning] %s" % line)
		_log(format_fallback_line("sidecar.warning", line))
		surfaced += 1
	return surfaced


## Surface any unresolved-profile warnings delivered via `initialize.packIntake.warnings`
## when not already ingested from stderr.
func ingest_pack_intake(handshake: Dictionary) -> int:
	var intake_v: Variant = handshake.get("packIntake", {})
	if not (intake_v is Dictionary):
		return 0
	var warnings_v: Variant = (intake_v as Dictionary).get("warnings", [])
	if not (warnings_v is Array):
		return 0
	var surfaced := 0
	for w_v: Variant in (warnings_v as Array):
		if not (w_v is Dictionary):
			continue
		var w := w_v as Dictionary
		var line := "[sidecar] warning [%s] %s: %s" % [
			String(w.get("code", "WARNING")),
			String(w.get("path", "")),
			String(w.get("message", "")),
		]
		var key := _warning_dedup_key(line)
		if _seen_sidecar_warnings.has(key):
			continue
		_seen_sidecar_warnings[key] = true
		diagnostics.append("[warning] %s" % line)
		_log(format_fallback_line("sidecar.warning", line))
		surfaced += 1
	return surfaced


## Surface a pack-load refusal from `--unresolved-ai-profile fail` visibly in transcript and log.
func report_startup_refusal(detail: String) -> void:
	diagnostics.append("[refused] %s" % detail)
	_log("[color=#c66]Sidecar refused pack: %s[/color]" % detail)


static func _warning_dedup_key(line: String) -> String:
	var idx := line.find("[sidecar] warning")
	return line.substr(idx) if idx >= 0 else line


func _log(line: String) -> void:
	transcript.append(line)
	narrated.emit(line)


## An out-of-band notice. Surfaced to a player-facing log if a UI wants it, but never part
## of the transcript the replay comparison uses.
func _note(line: String) -> void:
	diagnostics.append(line)
	narrated.emit(line)


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
	if diorama.get("room"):
		diorama.get("room").call("face_player", to.position - from.position)
