## felt_mixer.gd — play AudioCommand[] without becoming a second sim.
##
## The engine names cue ids. This mixer owns buses, overlay stings, and ambient
## beds. A sting NEVER stops the zone stem (Wwise default; v3.10 contract).
## Hashable world state is not touched here.
extends Node

const STEM_BUS := "Music"
const STING_BUS := "Music"
const AMBIENT_BUS := "Ambient"
const SFX_BUS := "Sfx"
const VOICE_BUS := "Voice"

## Cue ids currently holding a looping stem / bed. Tests read these.
var stem_id := ""
var stem_stopped := false
var beds: Dictionary = {}
var last_sting := ""
var executed: Array = []
var mute := false

var _stem: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _bed_players: Dictionary = {}


func _ready() -> void:
	_stem = _make_player("Stem", STEM_BUS)
	_sting = _make_player("Sting", STING_BUS)
	_sfx = _make_player("Sfx", SFX_BUS)
	_voice = _make_player("Voice", VOICE_BUS)


func stem_alive() -> bool:
	return not stem_id.is_empty() and not stem_stopped


## Execute one composed beat. Order is the engine's; we do not reorder.
func execute(commands: Array) -> void:
	for item: Variant in commands:
		if not (item is Dictionary):
			continue
		var cmd: Dictionary = item
		executed.append(cmd)
		_apply_state(cmd)
		if mute or not is_inside_tree():
			continue
		_audible(cmd)


func _apply_state(cmd: Dictionary) -> void:
	var domain := String(cmd.get("domain", ""))
	var action := String(cmd.get("action", ""))
	var resource := String(cmd.get("resourceId", ""))
	if domain == "music":
		if action == "sting":
			last_sting = resource
			# Overlay. The stem id is left alone on purpose.
		elif action == "play":
			stem_id = resource
			stem_stopped = false
		elif action == "stop":
			stem_stopped = true
	elif domain == "ambient":
		if action == "start" or action == "play":
			beds[resource] = true
		elif action == "stop":
			beds.erase(resource)


func _audible(cmd: Dictionary) -> void:
	var domain := String(cmd.get("domain", ""))
	var action := String(cmd.get("action", ""))
	var resource := String(cmd.get("resourceId", ""))
	if domain == "music" and action == "sting":
		_play(_sting, _tone_for(resource, 0.35, false))
		return
	if domain == "music" and action == "play":
		_play(_stem, _tone_for(resource, 2.0, true))
		return
	if domain == "music" and action == "stop":
		if _stem:
			_stem.stop()
		return
	if domain == "ambient" and (action == "start" or action == "play"):
		var p := _bed_player(resource)
		_play(p, _tone_for(resource, 3.0, true))
		return
	if domain == "ambient" and action == "stop":
		var existing: AudioStreamPlayer = _bed_players.get(resource) as AudioStreamPlayer
		if existing:
			existing.stop()
		return
	if domain == "sfx":
		_play(_sfx, _tone_for(resource, 0.12, false))
		return
	if domain == "voice":
		_play(_voice, _tone_for(resource, 0.4, false))


func _bed_player(resource: String) -> AudioStreamPlayer:
	if _bed_players.has(resource):
		return _bed_players[resource] as AudioStreamPlayer
	var p := _make_player("Bed_%s" % resource, AMBIENT_BUS)
	_bed_players[resource] = p
	return p


func _make_player(node_name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus
	add_child(p)
	return p


func _play(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if player == null:
		return
	player.stream = stream
	player.play()


## Procedural stand-in for CORE_SOUND_PACK. Real files can replace this later;
## the mixer contract is the cue id, not the waveform.
func _tone_for(resource: String, seconds: float, loop: bool) -> AudioStreamWAV:
	var freq := 220.0
	if resource.contains("dread") or resource.contains("drone"):
		freq = 90.0
	elif resource.contains("sting") or resource.contains("victory"):
		freq = 660.0
	elif resource.contains("defeat") or resource.contains("critical"):
		freq = 110.0
	elif resource.contains("calm") or resource.contains("white"):
		freq = 180.0
	elif resource.contains("alert") or resource.contains("warning"):
		freq = 440.0
	var mix := 22050
	var frames := maxi(int(mix * seconds), 64)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var env := 1.0
		if not loop:
			env = 1.0 - float(i) / float(frames)
		var sample := int(sin(TAU * freq * float(i) / float(mix)) * 8000.0 * env)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
	return stream
