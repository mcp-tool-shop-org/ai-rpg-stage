## felt_voice.gd — dialogue-only spoken output.
##
## Speaks SpeakerCue.text. Asides stay on the log. Optional HTTP embedder
## (`AI_RPG_TTS_URL`); without it, the mixer already plays a voice-domain tone
## and this node records the line so tests can see it was the spoken one.
extends Node

var spoken: Array[String] = []


func speak(cue: Dictionary) -> void:
	var text := String(cue.get("text", "")).strip_edges()
	if text.is_empty():
		return
	spoken.append(text)
	var url := OS.get_environment("AI_RPG_TTS_URL").strip_edges()
	if url.is_empty() or not is_inside_tree():
		return
	# Optional. A missing embedder must not stall the turn.
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	var body := JSON.stringify({
		"model": "tts-1",
		"input": text,
		"voice": String(cue.get("voiceId", "alloy")),
		"speed": cue.get("speed", 1.0),
	})
	req.request(
		url.rstrip("/") + "/v1/audio/speech",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		body,
	)
