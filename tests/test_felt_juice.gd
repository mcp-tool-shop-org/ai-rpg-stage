## test_felt_juice.gd — lie budget shakes the camera offset, never the bound node.
extends RefCounted

const FeltJuice := preload("res://stage/felt_juice.gd")


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "juice needs a camera in a tree")
		return

	var host := Node2D.new()
	tree.root.add_child(host)
	var cam := Camera2D.new()
	cam.name = "Cam"
	host.add_child(cam)
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(112, 136)
	host.add_child(player)

	var juice: Node = FeltJuice.new()
	host.add_child(juice)
	await tree.process_frame

	var origin := player.position
	juice.call("apply", [{"type": "shake", "durationMs": 50}], cam)
	t.equals(cam.offset, Vector2(3, 2), "shake writes camera.offset")
	t.equals(player.position, origin, "shake does not move the bound player node")

	juice.set("enabled", false)
	cam.offset = Vector2(9, 9)
	juice.call("apply", [{"type": "shake", "durationMs": 50}], cam)
	t.equals(cam.offset, Vector2.ZERO, "disabled juice zeros offset and does not shake")
	t.equals(player.position, origin, "disabled juice still does not move the player")

	host.queue_free()
	await tree.process_frame
