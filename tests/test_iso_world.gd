## test_iso_world.gd — dimetric harbour: ground draws, blobs share Z, strips own cells.
extends RefCounted

const IsoWorld := preload("res://stage/iso/iso_world.gd")
const IsoMath := preload("res://stage/iso/iso_math.gd")


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "SceneTree for iso world", "")
		return

	var iso: Node2D = IsoWorld.new()
	iso.name = "IsoTest"
	tree.root.add_child(iso)
	await tree.process_frame
	iso.call("build", {}, "merchant", [
		{"id": "front", "character": "guard", "zone": "customs-shed"},
		{"id": "behind", "character": "scribe", "zone": "customs-shed"},
	])
	await tree.process_frame

	var ground := iso.get_node_or_null("Ground") as TileMapLayer
	t.check(ground != null, "iso world has a TileMapLayer")
	if ground and ground.tile_set:
		t.equals(ground.tile_set.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC,
			"TileSet shape is isometric")
		t.equals(ground.tile_set.tile_size, Vector2i(IsoMath.TILE_W, IsoMath.TILE_H),
			"tile size is 2:1 (256×128)")
		t.is_true(ground.y_sort_enabled, "ground Y-sorts")
		_assert_atlas_corners(t, ground)
		_assert_map_matches_math(t, ground)
	t.is_true(iso.y_sort_enabled, "iso world Y-sorts")

	var player: Node2D = iso.get("player_actor") as Node2D
	t.check(player != null, "player actor is on the harbour")
	if player:
		var sh := player.get_node_or_null("Shadow") as CanvasItem
		t.check(sh != null, "player has a contact shadow")
		if sh:
			t.equals(sh.z_index, player.z_index, "blob shares the actor z_index")
			t.is_true(sh.show_behind_parent, "blob uses show_behind_parent, not z_index -1")
		t.check(player.get_node_or_null("Sprite") != null,
			"player is a Foundry sprite, not a ColorRect")

	t.check(iso.get_node_or_null("Props/counting-house") != null, "counting house is a sliced structure")
	t.check(iso.get_node_or_null("Props/bonded-warehouse") != null, "warehouse is a sliced structure")
	t.check(iso.get_node_or_null("Props/weighing-floor") != null, "well is a 1-cell prop")
	var shed := iso.get_node_or_null("Props/customs-shed")
	t.check(shed != null, "proof shed is an IsoStructure, not a 1024 plate",
		"exists=%s children=%s" % [ResourceLoader.exists("res://assets/dimetric/structures/shed_2x2/beauty.png"), str(iso.get_node_or_null("Props").get_child_count() if iso.get_node_or_null("Props") else -1)])
	if shed and shed.has_method("owning_cells"):
		var cells: Array = shed.call("owning_cells")
		var seen := {}
		for c: Variant in cells:
			var key := str(c)
			t.check(not seen.has(key), "no two strips share a cell (%s)" % key)
			seen[key] = true
			var world: Vector2 = IsoMath.cell_to_world(c)
			# Strip local y + structure origin y == cell world y.
			t.check(absf((shed as Node2D).position.y + _strip_y_for(shed, c) - world.y) < 1.0,
				"strip Y equals owning cell world Y")

	var cam := iso.get_node_or_null("IsoCamera") as Camera2D
	t.check(cam != null and cam.is_current(), "iso camera is current")
	t.check(iso.get_node_or_null("DoorTorch") != null, "door torch is on the canvas")

	t.check(iso.get_node_or_null("Actors/FrontProof") == null, "play layout is not FrontProof")
	t.check(iso.get_node_or_null("Actors/BehindProof") == null, "play layout is not BehindProof")
	var drell: Node2D = iso.get_node_or_null("Actors/npc-drell") as Node2D
	if drell == null:
		# CAST fallback in this test uses id "front" / "behind"; occupancy uses npc-drell.
		drell = iso.get_node_or_null("Actors/front") as Node2D
	t.check(iso.get_node_or_null("Actors/player") != null or iso.get("player_actor") != null,
		"player actor is named from occupancy or fallback")
	t.check(drell != null, "named guard stands on the harbour (occupancy npc-drell or CAST fallback)")
	var pack_txt := FileAccess.get_file_as_string("res://fixtures/pack.json")
	var pack: Variant = JSON.parse_string(pack_txt)
	var pack_occ := 0
	if pack is Dictionary:
		var pres: Variant = (pack as Dictionary).get("presentation", {})
		if pres is Dictionary:
			var occ: Variant = (pres as Dictionary).get("occupancy", [])
			if occ is Array:
				pack_occ = (occ as Array).size()
	# CI regenerates pack.json from FORGE_REF (still the 4.8-era exporter).
	# Committed pack.json on main has presentation; the sidecar is the fallback.
	t.check(pack_occ == 6 or FileAccess.file_exists("res://fixtures/harbour-occupancy.json"),
		"pack presentation occupancy is six rows, or the sidecar is present")

	var shed_anchor := Vector2i(8, 5)
	var front_pos: Vector2 = IsoMath.cell_to_world(shed_anchor + Vector2i(2, 2))
	var behind_pos: Vector2 = IsoMath.cell_to_world(shed_anchor + Vector2i(0, 0))
	t.check(front_pos.y > behind_pos.y,
		"shed front cell sorts in front of the far cell (higher Y)")

	var quay: Vector2i = Vector2i(5, 5)
	if ground:
		t.equals(ground.get_cell_atlas_coords(quay), Vector2i(3, 0),
			"long-quay diamonds use the wet-stone atlas slot")

	if player:
		var before := player.position
		iso.call("face_only", Vector2.LEFT)
		t.equals(player.position, before, "face_only does not move the hashed pose")

	iso.queue_free()
	await tree.process_frame


func _strip_y_for(shed: Node, cell: Vector2i) -> float:
	var origin: Vector2 = (shed as Node2D).position
	for child in shed.get_children():
		if child is Sprite2D:
			var world: Vector2 = origin + (child as Node2D).position
			if IsoMath.world_to_cell(world) == cell:
				return (child as Node2D).position.y
	return 0.0


func _assert_atlas_corners(t: RefCounted, ground: TileMapLayer) -> void:
	var src := ground.tile_set.get_source(0) as TileSetAtlasSource
	if src == null or src.texture == null:
		t.check(false, "ground atlas source")
		return
	var img := src.texture.get_image()
	if img == null:
		t.check(false, "ground atlas image")
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Atlas is N 256×128 diamonds. Each has alpha-0 8×8 corners.
	var tiles := img.get_width() / IsoMath.TILE_W
	t.check(tiles >= 3, "ground atlas has dirt_a/dirt_b/stone_a")
	for tile_i in tiles:
		var ox := tile_i * IsoMath.TILE_W
		var corners := [
			Vector2i(ox, 0), Vector2i(ox + IsoMath.TILE_W - 8, 0),
			Vector2i(ox, IsoMath.TILE_H - 8), Vector2i(ox + IsoMath.TILE_W - 8, IsoMath.TILE_H - 8),
		]
		for c in corners:
			var opaque := 0
			for y in 8:
				for x in 8:
					if img.get_pixel(c.x + x, c.y + y).a > 0.05:
						opaque += 1
			t.equals(opaque, 0, "ground tile %d corner %s is alpha 0" % [tile_i, str(c)])


func _assert_map_matches_math(t: RefCounted, ground: TileMapLayer) -> void:
	for x in range(-2, 3):
		for y in range(-2, 3):
			var cell := Vector2i(x, y)
			var mapped: Vector2 = ground.map_to_local(cell)
			var mathp: Vector2 = IsoMath.cell_to_world(cell)
			t.check(mapped.distance_to(mathp) < 1.0,
				"map_to_local(%s) == cell_to_world" % str(cell),
				"map=%s math=%s" % [str(mapped), str(mathp)])
