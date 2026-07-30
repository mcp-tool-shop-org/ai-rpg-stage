## screenshot.gd — render the diorama and write a PNG.
##
##   godot --path . --script res://tools/screenshot.gd --resolution 1600x900 -- --out=shot.png
##
## Deliberately NOT headless: `--headless` uses a dummy rasterizer, so a "screenshot"
## taken under it is a blank image. The whole point of this file is to produce something
## a person can look at, and the studio has a standing rule about never describing
## generated output without opening it — which applies to our own renders.
##
## Also usable to capture a specific state, so the re-dress can be seen rather than only
## asserted:
##
##   -- --zone=long-quay --tags=dressing:damaged,lighting:dim,props:rubble
extends SceneTree

const Diorama := preload("res://stage/diorama.gd")

## Frames to let pass before capturing. Lights, the tile atlas import and the sprite
## textures all settle over the first few frames; capturing on frame 1 catches a scene
## that is technically correct and visibly half-built.
const WARMUP_FRAMES := 12


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := _arg("out", "diorama.png")
	var zone := _arg("zone", "")
	var tags_raw := _arg("tags", "")

	# Load the real SCENE rather than constructing a Diorama, so the capture includes the
	# playable layer — the prose panel and the list of doors. A screenshot of the diorama
	# without them shows the set and not the thing a person uses.
	#
	# The playable layer reads `--attach=host:port` from the command line itself, so with a
	# sim running this captures a LIVE session; without one it captures the standing set and
	# says so on screen.
	change_scene_to_file("res://stage/diorama.tscn")
	await process_frame
	await process_frame
	var d: Node2D = current_scene as Node2D
	if d == null:
		printerr("diorama scene did not load")
		quit(1)
		return

	# Extra frames when attached: the handshake, snapshot and first prose all take a round
	# trip, and capturing before they land shows an empty log.
	if not _arg("attach", "").is_empty():
		for _w in range(90):
			await process_frame

	if not zone.is_empty():
		var tags: Array = [] if tags_raw.is_empty() else Array(tags_raw.split(",", false))
		d.call("apply_zone_state", zone, tags)
		print("state: zone=%s tags=%s" % [zone, str(tags)])

	# `--stride=x,y --steps=N`: walk the player N real frames through the free-move
	# controller before capturing — movement, facing and gait exactly as a hand on the
	# keys would produce them, so the shot proves the walking rather than posing it.
	var stride_raw := _arg("stride", "")
	if not stride_raw.is_empty():
		var sp := stride_raw.split(",", false)
		if sp.size() == 2:
			var vec := Vector2(float(sp[0]), float(sp[1]))
			var steps := int(_arg("steps", "60"))
			var mover := d.get_node_or_null("Playable/FreeMove")
			if mover == null:
				printerr("no FreeMove under Playable — cannot stride")
				quit(1)
				return
			for _s in range(steps):
				mover.call("step", 1.0 / 60.0, vec)
			print("strode %d frames along %s" % [steps, str(vec)])
			await process_frame

	for _i in range(WARMUP_FRAMES):
		await process_frame

	var image := root.get_texture().get_image()
	var err := image.save_png(out)
	if err != OK:
		printerr("could not write %s (error %d)" % [out, err])
		quit(1)
		return

	print("wrote %s  (%dx%d)" % [out, image.get_width(), image.get_height()])
	quit(0)


func _arg(key: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback
