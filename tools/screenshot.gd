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

	var d: Node2D = Diorama.new()
	d.name = "Diorama"
	root.add_child(d)
	# The harness property learned in P3: a node added during `_initialize` is not in the
	# tree until the first frame, and building before then leaves every `get_tree()` null.
	await process_frame
	d.call("build")

	if not zone.is_empty():
		var tags: Array = [] if tags_raw.is_empty() else Array(tags_raw.split(",", false))
		d.call("apply_zone_state", zone, tags)
		print("state: zone=%s tags=%s" % [zone, str(tags)])

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
