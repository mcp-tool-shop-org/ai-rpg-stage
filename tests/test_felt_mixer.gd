## test_felt_mixer.gd — overlay stings do not kill the zone stem.
extends RefCounted

const FeltMixer := preload("res://stage/felt_mixer.gd")


func run(t: RefCounted) -> void:
	var mixer: Node = FeltMixer.new()

	mixer.call("execute", [
		{"domain": "music", "action": "play", "resourceId": "music_dread", "priority": 1, "timing": 0, "params": {}},
		{"domain": "ambient", "action": "start", "resourceId": "ambient_drone", "priority": 1, "timing": 0, "params": {}},
	])
	t.is_true(bool(mixer.call("stem_alive")), "zone stem is playing after entry")
	t.equals(mixer.get("stem_id"), "music_dread", "stem id is the zone track")
	t.is_true((mixer.get("beds") as Dictionary).has("ambient_drone"), "ambient bed started")

	mixer.call("execute", [
		{"domain": "music", "action": "sting", "resourceId": "music_victory_sting", "priority": 2, "timing": 0, "params": {}},
	])
	t.is_true(bool(mixer.call("stem_alive")), "sting does not kill the zone stem")
	t.equals(mixer.get("stem_id"), "music_dread", "stem id unchanged after sting")
	t.equals(mixer.get("last_sting"), "music_victory_sting", "sting id recorded")
	t.is_true((mixer.get("beds") as Dictionary).has("ambient_drone"), "ambient bed survives a sting")

	mixer.call("execute", [
		{"domain": "music", "action": "stop", "resourceId": "music_dread", "priority": 1, "timing": 0, "params": {}},
	])
	t.is_false(bool(mixer.call("stem_alive")), "an explicit stop does kill the stem")

	var stream: Variant = mixer.call("_stream_for", "music_dread", 2.0, true)
	t.check(stream != null, "cue id always resolves to a stream")
	var want_file := ResourceLoader.exists("res://assets/felt/music_dread.wav")
	t.equals(String(mixer.get("last_source")), "file" if want_file else "tone",
		"WAV at assets/felt/<id>.wav wins; otherwise the procedural stand-in")

	mixer.free()
