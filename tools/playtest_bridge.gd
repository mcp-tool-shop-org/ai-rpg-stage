# playtest_bridge.gd — autoload. Lets ai-playtest's model players walk the harbour.
#
#   node tools/play.mjs --playtest-port 7777     (starts the sim, then the stage headless)
#   godot --headless --path . -- --attach=127.0.0.1:47820 --playtest-port=7777
#
# Without --playtest-port this node switches itself off in _ready and costs nothing, so
# it is safe to leave registered. The boilerplate is ai-playtest's docs/engine-bridge.md
# listing, pasted; the four functions at the bottom are the stage's.
#
# WHAT A MODEL PLAYER CAN DO is exactly what a person at the keyboard can: walk through
# one of the doors the SIM lists for the zone it says you are in, or wait a round. The
# bridge calls the Playable's own `_walk` / `_wait_a_round`, so a playtest exercises the
# same path a person does — including a listed door that refuses you.
extends Node

var _server := TCPServer.new()
var _peer: StreamPeerTCP = null
var _buf := PackedByteArray()

func _ready() -> void:
	# (1) WITHOUT THIS THE BRIDGE DEADLOCKS. An autoload's process_mode is
	# INHERIT, and the root is PAUSABLE — so `get_tree().paused = true` stops
	# this node's own _process, and the bridge goes deaf exactly when the pause
	# protocol needs it awake.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var port := _port_from_args()
	if port == 0:
		set_process(false)
		return
	if _server.listen(port, "127.0.0.1") != OK:
		push_error("playtest bridge could not listen on %d" % port)
		set_process(false)
		return
	print("PLAYTEST_BRIDGE_PORT=%d" % port)

func _port_from_args() -> int:
	# (2) get_cmdline_user_args() returns ONLY what follows a bare `--`.
	# Launch without it and this silently returns 0 and the bridge never starts.
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()        # tolerate the mistake
	for arg in args:
		if arg.begins_with("--playtest-port="):
			return int(arg.split("=")[1])
	return 0

func _process(_delta: float) -> void:
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_peer.set_no_delay(true)            # (3) Nagle adds ~40ms to every turn
		_on_connect()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_peer = null
		_buf.clear()
		return

	# (4) Buffer BYTES and decode only complete lines. TCP splits wherever it
	# likes, so decoding each arrival with get_utf8_string() mangles any
	# multi-byte character that straddles a segment boundary — every em-dash and
	# accented name in your prose. This is the same defect class as decoding
	# stdout chunks independently; it bites here for the same reason.
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk: Array = _peer.get_data(available)
		if chunk[0] == OK:
			_buf.append_array(chunk[1])

	while true:
		var nl := _buf.find(0x0A)           # '\n'
		if nl < 0:
			break
		var line := _buf.slice(0, nl).get_string_from_utf8().strip_edges()
		_buf = _buf.slice(nl + 1)
		if line != "":
			_handle(line)

func _handle(line: String) -> void:
	var msg: Variant = JSON.parse_string(line)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var id: int = int(msg.get("id", 0))
	match msg.get("method", ""):
		"hello":
			_reply(id, {"protocol": 1, "game": ProjectSettings.get_setting("application/config/name"),
						"capabilities": ["step_until"]})
		"observe":
			_reply(id, await _observation())
		"act":
			_apply(msg.get("params", {}))
			# Only once you are ready again — see _advance_until below.
			var hit_cap := await _advance_until(is_ready_for_input, 600)
			var obs := await _observation()
			if hit_cap:
				obs["reason"] = "timeout"   # the game never came back; say so
			_reply(id, obs)
		"reset":
			await _reset()
			_reply(id, await _observation())
		"quit":
			var final := await _observation()
			final["done"] = true
			_reply(id, final)
			_peer.disconnect_from_host()
			_server.stop()
			get_tree().quit()

func _reply(id: int, result: Dictionary) -> void:
	# Guard: after a client drop _peer is dead and put_data crashes.
	if _peer == null or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	_peer.put_data((JSON.stringify({"id": id, "result": result}) + "\n").to_utf8_buffer())

## Advance frames until the game says it is ready, capped. A fixed frame count
## is wrong for anything whose actions resolve over a variable number of frames
## — which is most combat.
func _advance_until(ready: Callable, max_frames: int) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		if ready.call():
			return false
	return true    # hit the cap

# ---- the parts that are the stage's ----

const WAIT := "wait"

## The world as the sim left it the first time a seat looked, so every seat starts there.
var _start_save := ""
var _start_zone := ""
## How much of the session transcript the player model has already been shown.
var _cursor := 0
## The zone the last observation was taken in; a change means "describe where you are".
var _described_zone := ""
var _waited := false
var _fresh_world_pending := false

## What a client has been shown is per CONNECTION, not per process. Without this a second
## client (the hand probe, then a playtest) opened on a bare "You are in…" line: the first
## had already been given the room's description, and the bridge remembered that for it.
func _on_connect() -> void:
	var session := _session()
	_cursor = (session.get("transcript") as Array).size() if session != null else 0
	_described_zone = ""
	_waited = false
	# And a new client starts in the world the first seat saw, not wherever the last
	# client walked it to. The reload is async, so the next observation performs it.
	_fresh_world_pending = not _start_save.is_empty()

func _playable() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Playable") if scene != null else null

func _session() -> Node:
	var p := _playable()
	return p.get("session") if p != null else null

func _zone_name(id: String) -> String:
	var diorama: Node = _playable().get_parent()
	for z: Variant in ((diorama.get("pack") as Dictionary).get("zones", []) as Array):
		if String((z as Dictionary).get("id", "")) == id:
			return String((z as Dictionary).get("name", id))
	return id

## BBCode is for the RichTextLabel. The player model reads plain prose.
func _plain(line: String) -> String:
	var re := RegEx.create_from_string("\\[/?[a-z]+(=[^\\]]*)?\\]")
	return re.sub(line, "", true).strip_edges()

func _observation() -> Dictionary:
	var session := _session()
	if session == null:
		# The stage did not attach to a sim (no --attach, or the sim was not up). There is
		# nothing to play, and saying so ends the seat instead of letting it stall.
		return {"text": "The stage is not attached to a simulation. Nothing can be played.", "done": true, "reason": "stuck"}
	await _wait_attached()
	if _fresh_world_pending:
		_fresh_world_pending = false
		await _reset()
	if _start_save.is_empty():
		var saved: Dictionary = await _playable().get("client").call("request", "save", {})
		_start_save = String(saved.get("serialized", ""))
		_start_zone = String(session.call("player_zone"))

	var zone := String(session.call("player_zone"))
	var lines: Array[String] = []
	var transcript: Array = session.get("transcript")
	for i in range(_cursor, transcript.size()):
		var l := _plain(String(transcript[i]))
		if not l.is_empty():
			lines.append(l)
	_cursor = transcript.size()
	if _waited:
		# The Playable says this to a person directly, outside the session transcript.
		lines.push_front("You wait.")
		_waited = false
	if zone != _described_zone:
		# Entering a zone already narrates it; describe it here only when nothing did
		# (the opening screen, and after a reset).
		var place := _plain(String(_playable().get_parent().call("description_of", zone)))
		if not place.is_empty() and not lines.has(place):
			lines.append(place)
		_described_zone = zone

	var options: Array = []
	for door: String in _playable().call("_current_doors"):
		options.append({"id": door, "label": "Walk to %s" % _zone_name(door)})
	options.append({"id": WAIT, "label": "Wait a round"})

	var exits := ", ".join(options.slice(0, options.size() - 1).map(func(o: Dictionary) -> String: return String(o["label"]).trim_prefix("Walk to ")))
	lines.append("You are in %s. Doors: %s." % [_zone_name(zone), exits if not exits.is_empty() else "none"])
	return {
		"text": "\n\n".join(lines),
		"state": {"zone": zone, "zoneName": _zone_name(zone), "transcriptLines": transcript.size()},
		"actions": {"kind": "choice", "options": options},
		"done": false,
	}

## The Playable attaches asynchronously after the scene loads. A seat that connects in
## that window waits for the snapshot rather than reading a half-built stage.
func _wait_attached() -> void:
	for i in 600:
		var p := _playable()
		if p != null and p.get("client") != null and not String(_session().call("player_zone")).is_empty():
			return
		await get_tree().process_frame

func _apply(action: Dictionary) -> void:
	var p := _playable()
	if p == null:
		return
	var choice := String(action.get("id", ""))
	if String(action.get("kind", "")) == "line":
		choice = String(action.get("line", "")).strip_edges().to_lower()
	if choice == WAIT:
		_waited = true
		p.call("_wait_a_round")
		return
	var doors: Array = p.call("_current_doors")
	var index := doors.find(choice)
	if index < 0:
		# A typed line: accept a zone's name as well as its id.
		for i in range(doors.size()):
			if _zone_name(String(doors[i])).to_lower() == choice:
				index = i
	if index >= 0:
		p.call("_walk", index)

func is_ready_for_input() -> bool:
	var p := _playable()
	return p == null or not bool(p.get("_busy"))

## Back to the world the first seat saw: reload the sim's save, then put the stage's own
## idea of where the player stands back where it was. The sim is the truth; the session's
## zone is a cache of it, and a load emits no zone.entered to refresh that cache.
func _reset() -> void:
	var session := _session()
	if session == null or _start_save.is_empty():
		return
	var client: Node = _playable().get("client")
	await client.call("request", "load", {"serialized": _start_save})
	await client.call("snapshot")
	session.set("_player_zone", _start_zone)
	_cursor = (session.get("transcript") as Array).size()
	_described_zone = ""
	_playable().call("_refresh_doors")
