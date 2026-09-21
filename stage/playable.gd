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

const MAX_LINES := 14

var diorama: Node2D
var session: Node
var client: Node
var bus: Node

var _log: RichTextLabel
var _log_panel: Control
var _doors: RichTextLabel
var _status: Label
var _toast: RichTextLabel
var _lines: Array[String] = []
var _busy := false
var _toast_left := 0.0


func _ready() -> void:
	layer = 20
	diorama = get_parent() as Node2D
	_build_ui()

	var target := _attach_target()
	_wire_iso()
	if target.is_empty():
		_status.text = "not attached — run: node tools/play.mjs"
		_say("[i]The stage is standing on its own. Nothing is deciding anything.[/i]")
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
	_wire_iso()
	await client.call("snapshot")

	# Open on the zone the sim says the player is in, with its prose, so the first thing on
	# screen is the writing rather than a UI.
	var zone := String(session.call("player_zone"))
	_say(String(diorama.call("description_of", zone)))
	_refresh_doors()


func _input(event: InputEvent) -> void:
	if _busy:
		return
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return

	var key := (event as InputEventKey).keycode

	# Number keys walk. `advance` waits a round — which is how a shock reaches you.
	if session != null and key >= KEY_1 and key <= KEY_9:
		_walk(key - KEY_1)
	elif session != null and key == KEY_SPACE:
		_wait_a_round()
	elif key == KEY_J:
		if session != null and session.get("juice") != null:
			var j: Node = session.get("juice")
			j.set("enabled", not bool(j.get("enabled")))
			_status.text = "juice %s" % ("on" if bool(j.get("enabled")) else "off")
	elif key == KEY_M:
		if session != null and session.get("mixer") != null:
			var mx: Node = session.get("mixer")
			mx.set("mute", not bool(mx.get("mute")))
			_status.text = "audio %s" % ("muted" if bool(mx.get("mute")) else "on")
	elif key == KEY_I:
		if _log_panel:
			_log_panel.visible = not _log_panel.visible
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
	var doors := _current_doors()
	for i in range(doors.size()):
		text += "  [%d] %s\n" % [i + 1, name_of.call(doors[i])]
	text += "  [space] wait   [i] log   [j] juice   [m] mute   [esc] leave"
	_doors.text = text


func _say(line: String) -> void:
	if line.strip_edges().is_empty():
		return
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	if _log:
		_log.text = "\n\n".join(_lines)
	if _toast:
		_toast.text = line
		_toast.visible = true
		_toast_left = 4.0


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	if _toast_left <= 0.0 and _toast:
		_toast.visible = false


func _wire_iso() -> void:
	if diorama == null:
		return
	var iso: Node = diorama.get("iso")
	if iso == null:
		return
	if iso.has_signal("move_requested") and not iso.move_requested.is_connected(_on_iso_move):
		iso.move_requested.connect(_on_iso_move)


func _on_iso_move(zone_id: String) -> void:
	if _busy:
		return
	if session != null:
		_busy = true
		await session.call("walk_to", zone_id)
		_refresh_doors()
		_busy = false
		return
	var iso: Node = diorama.get("iso")
	if iso:
		iso.call("walk_player_to", zone_id, Vector2.DOWN)


# ── UI ────────────────────────────────────────────────────────

func _build_ui() -> void:
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status.offset_left = 20
	_status.offset_top = 14
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	_doors = RichTextLabel.new()
	_doors.bbcode_enabled = true
	_doors.fit_content = true
	_doors.scroll_active = false
	_doors.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_doors.offset_left = 20
	_doors.offset_top = 36
	_doors.offset_right = 720
	_doors.offset_bottom = 120
	_doors.add_theme_font_size_override("normal_font_size", 15)
	_doors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_doors)

	_toast = RichTextLabel.new()
	_toast.bbcode_enabled = true
	_toast.fit_content = true
	_toast.scroll_active = false
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.anchor_left = 0.2
	_toast.anchor_right = 0.8
	_toast.offset_top = -72
	_toast.offset_bottom = -16
	_toast.add_theme_font_size_override("normal_font_size", 16)
	_toast.modulate = Color(1, 1, 1, 0.92)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

	_log_panel = PanelContainer.new()
	_log_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_panel.offset_left = 80
	_log_panel.offset_right = -80
	_log_panel.offset_top = 80
	_log_panel.offset_bottom = -80
	_log_panel.visible = false
	add_child(_log_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_log_panel.add_child(margin)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 15)
	margin.add_child(_log)
