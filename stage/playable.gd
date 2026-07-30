## playable.gd — the part a person uses.
##
## C4's exit gate is not a screenshot and not a green suite: it is that the Director plays
## it. So this is input, a place to read the prose, and a list of doors — the smallest
## surface on which the four clauses are things that HAPPEN TO YOU rather than things a
## test asserts.
##
## Deliberately plain. A polished UI would be C5's business and would hide, behind its own
## complexity, whether the wire underneath actually works.
##
## THE CONTROL: number keys walk you through the door with that number. That is it. The
## doors listed are the sim's `neighbors` for the zone the sim says you are in — so the
## list is the world's, not the interface's, and a door that is listed can still refuse
## you, which is the whole point of the warehouse.
extends CanvasLayer

const Session := preload("res://stage/session.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")
const FreeMove := preload("res://stage/free_move.gd")

const MAX_LINES := 14

var diorama: Node2D
var session: Node
var client: Node
var bus: Node
var mover: Node

var _log: RichTextLabel
var _doors: RichTextLabel
var _status: Label
var _lines: Array[String] = []
var _busy := false


func _ready() -> void:
	diorama = get_parent() as Node2D
	_build_ui()

	# The sprite walks whether or not a sim is attached. Movement inside a zone is
	# presentation and needs nobody's permission; only DOORS need the world to decide.
	mover = FreeMove.new()
	mover.name = "FreeMove"
	mover.call("setup", diorama, null)
	mover.set("narrate", Callable(self, "_say"))
	add_child(mover)

	var target := _attach_target()
	if target.is_empty():
		_status.text = "sandbox — walk with arrows / WASD · run node tools/play.mjs for the world"
		_say("[i]The stage is standing on its own. You can walk; nothing can decide.[/i]")
		_say("Start the simulation with [b]node tools/play.mjs[/b] to play.")
		return

	await _attach(target)


## `--attach=host:port`, passed after `--` by the launcher.
func _attach_target() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--attach="):
			return a.substr(9)
	return ""


func _attach(target: String) -> void:
	var parts := target.split(":", false)
	if parts.size() != 2:
		_status.text = "bad --attach target: %s" % target
		return

	bus = EventBus.new()
	bus.name = "Bus"
	add_child(bus)

	client = NetworkClient.new()
	client.name = "NetworkClient"
	client.bus = bus
	add_child(client)

	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.call("setup", diorama, client, bus)
	session.narrated.connect(_say)
	mover.call("setup", diorama, session)
	session.zone_entered.connect(func(_zone: String) -> void: _refresh_doors())

	# The session already routes these to `diagnostics` and emits them on `narrated`, so
	# subscribing here as well would show each one twice. The UI shows what the session
	# narrates; the split between transcript and diagnostics lives in the session.

	_status.text = "attaching to %s…" % target
	var handshake: Dictionary = await client.call("attach", parts[0], int(parts[1]), "ai-rpg-stage")
	if handshake.is_empty():
		_status.text = "could not attach to %s" % target
		_say("[color=#c66]Could not attach. Is the sim running?[/color]")
		return

	_status.text = "attached — %s" % String(handshake.get("engineVersion", "?"))
	await client.call("snapshot")

	# Open on the zone the sim says the player is in, with its prose, so the first thing on
	# screen is the writing rather than a UI.
	var zone := String(session.call("player_zone"))
	_say(String(diorama.call("description_of", zone)))
	_refresh_doors()


func _input(event: InputEvent) -> void:
	if session == null or _busy:
		return
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return

	var key := (event as InputEventKey).keycode

	# Number keys walk. `advance` waits a round — which is how a shock reaches you.
	if key >= KEY_1 and key <= KEY_9:
		_walk(key - KEY_1)
	elif key == KEY_SPACE:
		_wait_a_round()
	elif key == KEY_ESCAPE:
		if client != null:
			client.call("detach")
		get_tree().quit()


func _walk(index: int) -> void:
	var doors := _current_doors()
	if index >= doors.size():
		return
	_busy = true
	await session.call("walk_to", doors[index])
	_refresh_doors()
	_busy = false


func _wait_a_round() -> void:
	_busy = true
	_say("[i]You wait.[/i]")
	await session.call("advance")
	_refresh_doors()
	_busy = false


## The doors out of the zone the SIM says you are in, from its own `neighbors`.
##
## Read off the fixture rather than the scene tree because the wire's zone graph is the
## authority on what connects to what; the scene is where those zones are DRAWN.
func _current_doors() -> Array[String]:
	var zone := String(session.call("player_zone"))
	var pack: Dictionary = diorama.get("pack")
	for z: Variant in (pack.get("zones", []) as Array):
		var zd: Dictionary = z as Dictionary
		if String(zd.get("id", "")) == zone:
			var out: Array[String] = []
			for n: Variant in (zd.get("neighbors", []) as Array):
				out.append(String(n))
			return out
	return []


func _refresh_doors() -> void:
	var zone := String(session.call("player_zone"))
	var name_of := func(id: String) -> String:
		var pack: Dictionary = diorama.get("pack")
		for z: Variant in (pack.get("zones", []) as Array):
			if String((z as Dictionary).get("id", "")) == id:
				return String((z as Dictionary).get("name", id))
		return id

	var text := "[b]%s[/b]\n" % name_of.call(zone)
	text += "[i]walk: arrows / WASD — step onto a doorway[/i]\n"
	var doors := _current_doors()
	for i in range(doors.size()):
		text += "  [%d] %s\n" % [i + 1, name_of.call(doors[i])]
	text += "\n  [space] wait a round\n  [esc] leave"
	_doors.text = text


func _say(line: String) -> void:
	if line.strip_edges().is_empty():
		return
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_log.text = "\n\n".join(_lines)


# ── UI ────────────────────────────────────────────────────────

func _build_ui() -> void:
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_panel.offset_top = -260
	log_panel.offset_left = 16
	log_panel.offset_right = -360
	log_panel.offset_bottom = -16
	add_child(log_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	log_panel.add_child(margin)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.add_theme_font_size_override("normal_font_size", 15)
	margin.add_child(_log)

	var door_panel := PanelContainer.new()
	door_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	door_panel.offset_left = -330
	door_panel.offset_right = -16
	door_panel.offset_top = 16
	door_panel.offset_bottom = 260
	add_child(door_panel)

	var dmargin := MarginContainer.new()
	dmargin.add_theme_constant_override("margin_left", 14)
	dmargin.add_theme_constant_override("margin_right", 14)
	dmargin.add_theme_constant_override("margin_top", 10)
	dmargin.add_theme_constant_override("margin_bottom", 10)
	door_panel.add_child(dmargin)

	_doors = RichTextLabel.new()
	_doors.bbcode_enabled = true
	_doors.add_theme_font_size_override("normal_font_size", 15)
	dmargin.add_child(_doors)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status.offset_left = 20
	_status.offset_top = 14
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(1, 1, 1, 0.55)
	add_child(_status)
