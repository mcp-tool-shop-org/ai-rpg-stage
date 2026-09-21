## iso_structure.gd — a building sliced into 128 px strips, one drawable per diamond.
##
## Godot will not Y-sort a multi-cell tile (#92682). A 1024² plate is one sort key.
## This node takes an ANDON-passing RGBA plate and a footprint in cells, cuts
## vertical strips, and parents each strip at the world point of one footprint
## cell (left-to-right by screen X). Actors walking beside a wall sort against
## that wall's strip, not the whole house.
extends Node2D

const IsoMath := preload("res://stage/iso/iso_math.gd")

const STRIP_PX := 128

var footprint := Vector2i(2, 2)
var anchor := Vector2i.ZERO
var strips: Array[Sprite2D] = []


func setup(texture: Texture2D, footprint_cells: Vector2i, anchor_cell: Vector2i) -> void:
	footprint = footprint_cells
	anchor = anchor_cell
	y_sort_enabled = true
	if texture == null:
		return
	var img := texture.get_image()
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var n := maxi(1, w / STRIP_PX)
	var cells := _footprint_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var wa := IsoMath.cell_to_world(a)
		var wb := IsoMath.cell_to_world(b)
		if wa.x == wb.x:
			return wa.y < wb.y
		return wa.x < wb.x
	)
	var origin := IsoMath.cell_to_world(anchor)
	position = origin
	for i in n:
		var cell: Vector2i = cells[mini(i, cells.size() - 1)]
		if i < cells.size():
			cell = cells[i]
		var col := Image.create(STRIP_PX, h, false, Image.FORMAT_RGBA8)
		col.fill(Color(0, 0, 0, 0))
		var src_x := i * STRIP_PX
		if src_x >= w:
			break
		col.blit_rect(img, Rect2i(src_x, 0, mini(STRIP_PX, w - src_x), h), Vector2i.ZERO)
		var spr := Sprite2D.new()
		spr.name = "Strip%d" % i
		spr.texture = ImageTexture.create_from_image(col)
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# Foot of this column: lowest opaque pixel, centred in the strip.
		var foot_y := _foot_y(col)
		spr.offset = Vector2(-float(STRIP_PX) * 0.5, -float(foot_y))
		spr.position = IsoMath.cell_to_world(cell) - origin
		spr.y_sort_enabled = true
		add_child(spr)
		strips.append(spr)


func owning_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in strips:
		out.append(IsoMath.world_to_cell(position + s.position))
	return out


func _footprint_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in footprint.x:
		for y in footprint.y:
			out.append(anchor + Vector2i(x, y))
	return out


static func _foot_y(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				return y
	return img.get_height() - 1
