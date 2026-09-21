## iso_world.gd — one continuous dimetric harbour.
##
## Ground tiles come from assets/dimetric/ (ANDON-passing 256×128 diamonds).
## The eight plates under assets/iso/ are dead and are never loaded.
## Buildings are IsoStructure strips. Intra-zone walking is presentation;
## crossing a neighbour zone is the committed `move`.
extends Node2D

const IsoMath := preload("res://stage/iso/iso_math.gd")
const IsoActor := preload("res://stage/iso/iso_actor.gd")
const IsoProp := preload("res://stage/iso/iso_prop.gd")
const IsoStructure := preload("res://stage/iso/iso_structure.gd")

const DIRT_A := "res://assets/dimetric/ground/dirt_a.png"
const DIRT_B := "res://assets/dimetric/ground/dirt_b.png"
const STONE := "res://assets/dimetric/ground/stone_a.png"
const STONE_WET := "res://assets/dimetric/ground/stone_wet.png"
const LIB := "res://assets/dimetric/"
const OCCUPANCY_PATH := "res://fixtures/harbour-occupancy.json"
const PACK_PATH := "res://fixtures/pack.json"

## Zone id → ANDON-passing structure (path under LIB, footprint cells).
const ZONE_STRUCTURE := {
	"counting-house": { "path": "structures/counting_house/beauty.png", "fp": Vector2i(3, 3) },
	"bonded-warehouse": { "path": "structures/warehouse/beauty.png", "fp": Vector2i(3, 3) },
	"customs-shed": { "path": "structures/shed_2x2/beauty.png", "fp": Vector2i(2, 2) },
	"crooked-stair": { "path": "structures/stair/beauty.png", "fp": Vector2i(2, 3) },
}
const ZONE_PROP := {
	"weighing-floor": "props/well_1x1/beauty.png",
	"long-quay": "props/cart_1x1/beauty.png",
}

const ZONE_CELLS := {
	"counting-house": Vector2i(2, 2),
	"weighing-floor": Vector2i(5, 2),
	"bonded-warehouse": Vector2i(8, 2),
	"long-quay": Vector2i(5, 5),
	"customs-shed": Vector2i(8, 5),
	"crooked-stair": Vector2i(5, 8),
}

## 3×3 diamond around each zone anchor. Intra-zone clicks stay here.
const ZONE_SPAN := 3

signal cell_clicked(cell: Vector2i, zone_id: String)
signal move_requested(zone_id: String)

var ground: TileMapLayer
var cam: Camera2D
var actors: Node2D
var props: Node2D
var hover: Polygon2D
var player_actor: Node2D
var current_zone := "counting-house"
var _zone_world: Dictionary = {}
var _walk_tween: Tween
var _torch: PointLight2D
var _presentation_cache: Dictionary = {}
var _presentation_loaded := false


func build(_pack: Dictionary, player_character: String, cast: Array) -> void:
	y_sort_enabled = true
	z_index = 0
	_build_ground()
	_build_camera()
	_build_hover()
	props = Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	props.z_index = 0
	add_child(props)
	actors = Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	actors.z_index = 0
	add_child(actors)
	_place_buildings()
	_place_torch()
	_place_cast(player_character, cast)
	look_at_zone(current_zone)


func world_pos_of(zone_id: String) -> Vector2:
	if _zone_world.has(zone_id):
		return _zone_world[zone_id]
	return IsoMath.cell_to_world(_anchor(zone_id))


func zone_at_cell(cell: Vector2i) -> String:
	for zone_id: Variant in _zone_ids():
		var id := String(zone_id)
		var a: Vector2i = _anchor(id)
		if cell.x >= a.x and cell.x < a.x + ZONE_SPAN and cell.y >= a.y and cell.y < a.y + ZONE_SPAN:
			return id
	return ""


func look_at_zone(zone_id: String) -> void:
	current_zone = zone_id
	if cam:
		cam.position = world_pos_of(zone_id)


## Presentation after a committed zone change. The hashed thing is zoneId;
## the sprite may tween.
func walk_player_to(zone_id: String, motion: Vector2) -> void:
	if player_actor == null:
		return
	if player_actor.has_method("face"):
		player_actor.call("face", motion)
	var dest := IsoMath.cell_to_world(_stand_cell(zone_id))
	_tween_actor_to(dest)
	look_at_zone(zone_id)


func face_only(motion: Vector2) -> void:
	if player_actor and player_actor.has_method("face"):
		player_actor.call("face", motion)


func walk_to_cell(cell: Vector2i) -> void:
	if player_actor == null:
		return
	var dest := IsoMath.cell_to_world(cell)
	var motion: Vector2 = dest - player_actor.position
	if player_actor.has_method("face"):
		player_actor.call("face", motion)
	_tween_actor_to(dest)


func pick_at(global_pos: Vector2) -> Vector2i:
	if cam:
		cam.force_update_scroll()
	var local := to_local(global_pos)
	return IsoMath.pick_cell(local)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if cam:
				cam.force_update_scroll()
			var cell := pick_at(get_global_mouse_position())
			var zone := zone_at_cell(cell)
			cell_clicked.emit(cell, zone)
			_handle_click(cell, zone)


func _handle_click(cell: Vector2i, zone: String) -> void:
	if zone.is_empty():
		walk_to_cell(cell)
		return
	if zone == current_zone:
		walk_to_cell(cell)
		return
	move_requested.emit(zone)


func _tween_actor_to(dest: Vector2) -> void:
	if player_actor == null:
		return
	if _walk_tween and _walk_tween.is_valid():
		_walk_tween.kill()
	var dist := player_actor.position.distance_to(dest)
	var dur := clampf(dist / 220.0, 0.05, 1.0)
	_walk_tween = create_tween()
	_walk_tween.tween_property(player_actor, "position", dest, dur)
	_walk_tween.finished.connect(func() -> void:
		player_actor.position = Vector2(round(dest.x), round(dest.y))
	, CONNECT_ONE_SHOT)


func _update_hover(_screen_pos: Vector2) -> void:
	if hover == null or cam == null:
		return
	cam.force_update_scroll()
	var cell := pick_at(get_global_mouse_position())
	var c := IsoMath.cell_to_world(cell)
	var hw := float(IsoMath.TILE_W) * 0.5
	var hh := float(IsoMath.TILE_H) * 0.5
	hover.polygon = PackedVector2Array([
		Vector2(c.x, c.y - hh),
		Vector2(c.x + hw, c.y),
		Vector2(c.x, c.y + hh),
		Vector2(c.x - hw, c.y),
	])
	hover.visible = true


func _build_ground() -> void:
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.y_sort_enabled = true
	ground.z_index = 0
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tileset.tile_size = Vector2i(IsoMath.TILE_W, IsoMath.TILE_H)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = _ground_atlas()
	atlas.texture_region_size = Vector2i(IsoMath.TILE_W, IsoMath.TILE_H)
	atlas.use_texture_padding = true
	atlas.create_tile(Vector2i(0, 0))
	atlas.create_tile(Vector2i(1, 0))
	atlas.create_tile(Vector2i(2, 0))
	atlas.create_tile(Vector2i(3, 0))
	tileset.add_source(atlas, 0)
	ground.tile_set = tileset
	add_child(ground)
	for x in range(-2, 12):
		for y in range(-2, 12):
			var src := Vector2i(0, 0)
			if (x + y) % 5 == 0:
				src = Vector2i(2, 0)
			elif (x * 3 + y) % 2 == 0:
				src = Vector2i(1, 0)
			ground.set_cell(Vector2i(x, y), 0, src)
	_paint_quay_wet()


func _ground_atlas() -> Texture2D:
	var dirt_a := _load_rgba(DIRT_A, Color(0.45, 0.38, 0.28))
	var dirt_b := _load_rgba(DIRT_B, Color(0.42, 0.35, 0.25))
	var stone := _load_rgba(STONE, Color(0.32, 0.33, 0.34))
	var wet := _load_rgba(STONE_WET, Color(0.28, 0.30, 0.32))
	var img := Image.create(IsoMath.TILE_W * 4, IsoMath.TILE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.blit_rect(dirt_a, Rect2i(0, 0, IsoMath.TILE_W, IsoMath.TILE_H), Vector2i(0, 0))
	img.blit_rect(dirt_b, Rect2i(0, 0, IsoMath.TILE_W, IsoMath.TILE_H), Vector2i(IsoMath.TILE_W, 0))
	img.blit_rect(stone, Rect2i(0, 0, IsoMath.TILE_W, IsoMath.TILE_H), Vector2i(IsoMath.TILE_W * 2, 0))
	img.blit_rect(wet, Rect2i(0, 0, IsoMath.TILE_W, IsoMath.TILE_H), Vector2i(IsoMath.TILE_W * 3, 0))
	return ImageTexture.create_from_image(img)


func _paint_quay_wet() -> void:
	if ground == null:
		return
	var anchor: Vector2i = _anchor("long-quay")
	for x in ZONE_SPAN:
		for y in ZONE_SPAN:
			ground.set_cell(anchor + Vector2i(x, y), 0, Vector2i(3, 0))


func _load_rgba(path: String, fallback: Color) -> Image:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			var got := tex.get_image()
			if got:
				if got.get_format() != Image.FORMAT_RGBA8:
					got.convert(Image.FORMAT_RGBA8)
				# Never resize. ANDON already refused a wrong size.
				if got.get_size() == Vector2i(IsoMath.TILE_W, IsoMath.TILE_H):
					return got
	return _diamond_tile(fallback)


static func _diamond_tile(color: Color) -> Image:
	var img := Image.create(IsoMath.TILE_W, IsoMath.TILE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := IsoMath.TILE_W / 2.0
	var cy := IsoMath.TILE_H / 2.0
	for y in IsoMath.TILE_H:
		var t: float = absf(float(y) - cy) / cy
		var half: float = (1.0 - t) * cx
		var n: float = 1.0 - t * 0.18
		var c := Color(color.r * n, color.g * n, color.b * n, 1)
		var x0 := int(cx - half)
		var x1 := int(cx + half)
		for x in range(x0, x1):
			img.set_pixel(x, y, c)
	return img


func _build_camera() -> void:
	cam = Camera2D.new()
	cam.name = "IsoCamera"
	cam.enabled = true
	cam.zoom = Vector2(0.72, 0.72)
	add_child(cam)
	cam.make_current()


func _build_hover() -> void:
	hover = Polygon2D.new()
	hover.name = "Hover"
	hover.color = Color(1, 0.92, 0.55, 0.22)
	hover.z_index = 0
	hover.visible = false
	# Child of Ground so it is not a Y-sort rival of actors.
	ground.add_child(hover)


func _place_buildings() -> void:
	for zone_id: Variant in _zone_ids():
		var id := String(zone_id)
		var cell: Vector2i = _anchor(id)
		_zone_world[id] = IsoMath.cell_to_world(cell)
	for zone_id: Variant in ZONE_STRUCTURE.keys():
		var id := String(zone_id)
		var spec: Dictionary = ZONE_STRUCTURE[id]
		var tex := _load_texture(LIB + String(spec["path"]))
		if tex == null:
			continue
		var building: Node2D = IsoStructure.new()
		building.name = id
		props.add_child(building)
		building.call("setup", tex, spec["fp"], _anchor(id))
	for zone_id: Variant in ZONE_PROP.keys():
		var id := String(zone_id)
		var tex := _load_texture(LIB + String(ZONE_PROP[id]))
		if tex == null:
			continue
		var prop: Node2D = IsoProp.new()
		prop.name = id
		prop.position = IsoMath.cell_to_world(_anchor(id))
		prop.call("setup", tex)
		props.add_child(prop)
	# Harbour dressing — 1-cell props, not occupancy.
	_place_dressing_prop("barrel", "props/barrel_1x1/beauty.png", _anchor("long-quay") + Vector2i(-1, 0))
	_place_dressing_prop("crate", "props/crate_1x1/beauty.png", _anchor("long-quay") + Vector2i(1, 1))
	_place_dressing_prop("bollard", "props/bollard_1x1/beauty.png", _anchor("long-quay") + Vector2i(0, 1))


func _place_dressing_prop(node_name: String, rel: String, cell: Vector2i) -> void:
	var tex := _load_texture(LIB + rel)
	if tex == null:
		return
	var prop: Node2D = IsoProp.new()
	prop.name = node_name
	prop.position = IsoMath.cell_to_world(cell)
	prop.call("setup", tex)
	props.add_child(prop)


func _place_torch() -> void:
	# Plate is 256×256; sidecar light_px is (128, 72) from top-left; foot is
	# the near vertex at the bottom centre. Offset from the IsoProp origin.
	var torch_cell: Vector2i = _anchor("customs-shed") + Vector2i(1, 1)
	_place_dressing_prop("torch", "props/torch_1x1/beauty.png", torch_cell)
	_torch = PointLight2D.new()
	_torch.name = "DoorTorch"
	_torch.color = Color(1.0, 0.78, 0.45, 1)
	_torch.energy = 0.95
	_torch.height = 48.0
	_torch.texture_scale = 2.2
	_torch.shadow_enabled = false
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var light_tex := GradientTexture2D.new()
	light_tex.gradient = grad
	light_tex.width = 256
	light_tex.height = 256
	light_tex.fill = GradientTexture2D.FILL_RADIAL
	light_tex.fill_from = Vector2(0.5, 0.5)
	light_tex.fill_to = Vector2(0.5, 0.0)
	_torch.texture = light_tex
	_torch.position = IsoMath.cell_to_world(torch_cell) + Vector2(0, -183)
	add_child(_torch)


func _place_cast(player_character: String, cast: Array) -> void:
	var rows: Array = _occupancy_rows(player_character, cast)
	for item: Variant in rows:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var id := String(row.get("id", "npc"))
		var character := String(row.get("character", ""))
		var zone := String(row.get("zone", "counting-house"))
		var cell := _cell_of(row, zone)
		var actor: Node2D = IsoActor.new()
		actor.name = id
		actor.set_meta("zone", zone)
		actor.set_meta("cell", cell)
		actor.position = IsoMath.cell_to_world(cell)
		actors.add_child(actor)
		actor.call("setup", character)
		var facing := String(row.get("facing", ""))
		if not facing.is_empty() and actor.has_method("face_named"):
			actor.call("face_named", facing)
		if id == "player":
			player_actor = actor
	if player_actor == null:
		player_actor = IsoActor.new()
		player_actor.name = "player"
		player_actor.position = IsoMath.cell_to_world(_stand_cell("counting-house"))
		actors.add_child(player_actor)
		player_actor.call("setup", player_character)


## A spawn the sim named. Presentation: a free cell in that zone's 3×3, never
## a leftover cartesian (150, 150) from the hidden fourth-wall rooms.
func spawn_entity(zone_id: String, entity_id: String, index: int) -> Node2D:
	if actors == null:
		return null
	var anchor: Vector2i = _anchor(zone_id)
	var cell := Vector2i(anchor.x + ZONE_SPAN - 1, anchor.y + (index % ZONE_SPAN))
	var actor: Node2D = IsoActor.new()
	actor.name = "Spawn_%s" % entity_id
	actor.set_meta("entity_id", entity_id)
	actor.set_meta("zone", zone_id)
	actor.set_meta("cell", cell)
	actor.position = IsoMath.cell_to_world(cell)
	actors.add_child(actor)
	actor.call("setup", "fisherman")
	return actor


func _stand_cell(zone_id: String) -> Vector2i:
	return _anchor(zone_id) + Vector2i(ZONE_SPAN - 1, ZONE_SPAN - 1)


func _occupancy_rows(player_character: String, cast: Array) -> Array:
	var authored := _load_occupancy()
	if not authored.is_empty():
		return authored
	var rows: Array = []
	rows.append({
		"id": "player",
		"character": player_character,
		"zone": "counting-house",
		"cell": [_stand_cell("counting-house").x, _stand_cell("counting-house").y],
		"facing": "front",
	})
	for item: Variant in cast:
		if not (item is Dictionary):
			continue
		var m: Dictionary = item
		var zone := String(m.get("zone", "counting-house"))
		var cell := _stand_cell(zone)
		rows.append({
			"id": String(m.get("id", "npc")),
			"character": String(m.get("character", "")),
			"zone": zone,
			"cell": [cell.x, cell.y],
			"facing": "front",
		})
	return rows


func _load_occupancy() -> Array:
	var from_pack: Variant = _presentation().get("occupancy", [])
	if from_pack is Array and (from_pack as Array).size() > 0:
		return from_pack
	if not FileAccess.file_exists(OCCUPANCY_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OCCUPANCY_PATH))
	if parsed is Dictionary:
		var actors_v: Variant = (parsed as Dictionary).get("actors", [])
		if actors_v is Array:
			return actors_v
	return []


func _presentation() -> Dictionary:
	if _presentation_loaded:
		return _presentation_cache
	_presentation_loaded = true
	if FileAccess.file_exists(PACK_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_PATH))
		if parsed is Dictionary:
			var block: Variant = (parsed as Dictionary).get("presentation", {})
			if block is Dictionary:
				_presentation_cache = block
	return _presentation_cache


func _anchor(zone_id: String) -> Vector2i:
	var zc: Variant = _presentation().get("zoneCells", {})
	if zc is Dictionary and (zc as Dictionary).has(zone_id):
		var raw: Variant = (zc as Dictionary)[zone_id]
		if raw is Array and (raw as Array).size() >= 2:
			return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	return ZONE_CELLS.get(zone_id, Vector2i.ZERO)


func _zone_ids() -> Array:
	var zc: Variant = _presentation().get("zoneCells", {})
	if zc is Dictionary and (zc as Dictionary).size() > 0:
		return (zc as Dictionary).keys()
	return ZONE_CELLS.keys()


func _cell_of(row: Dictionary, zone: String) -> Vector2i:
	var raw: Variant = row.get("cell", [])
	var cell := _stand_cell(zone)
	if raw is Array and (raw as Array).size() >= 2:
		cell = Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	if not _cell_in_zone(cell, zone):
		return _stand_cell(zone)
	return cell


func _cell_in_zone(cell: Vector2i, zone: String) -> bool:
	var a: Vector2i = _anchor(zone)
	return cell.x >= a.x and cell.x < a.x + ZONE_SPAN and cell.y >= a.y and cell.y < a.y + ZONE_SPAN


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
