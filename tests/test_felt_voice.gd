## test_felt_voice.gd — only SpeakerCue.text is spoken.
extends RefCounted

const FeltVoice := preload("res://stage/felt_voice.gd")
const Session := preload("res://stage/session.gd")
const FeltMixer := preload("res://stage/felt_mixer.gd")
const FeltJuice := preload("res://stage/felt_juice.gd")


func run(t: RefCounted) -> void:
	var voice: Node = FeltVoice.new()
	voice.call("speak", {
		"entityId": "halle",
		"voiceId": "npc",
		"emotion": "cold",
		"speed": 1.0,
		"text": "The quay is closed.",
	})
	var spoken: Array = voice.get("spoken")
	t.equals(spoken.size(), 1, "one spoken line")
	t.equals(spoken[0], "The quay is closed.", "spoken text is the SpeakerCue line")

	# Session applies felt.speaker and ignores asides — asides are not on the payload.
	var session: Node = Session.new()
	session.set("mixer", FeltMixer.new())
	session.set("juice", FeltJuice.new())
	session.set("voice", voice)
	session.call("_apply_felt", {
		"felt": {
			"audio": [],
			"speaker": {
				"entityId": "halle",
				"voiceId": "npc",
				"emotion": "cold",
				"speed": 1.0,
				"text": "Seal first.",
			},
		},
	})
	spoken = voice.get("spoken")
	t.equals(spoken.size(), 2, "felt speaker is spoken")
	t.equals(spoken[1], "Seal first.", "second line is the felt speaker, not an aside")

	(session.get("mixer") as Node).free()
	(session.get("juice") as Node).free()
	session.free()
	voice.free()
