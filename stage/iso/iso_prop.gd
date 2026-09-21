## iso_prop.gd — a ≤1-cell object on the diamond. Buildings use IsoStructure.
extends Node2D

var sprite: Sprite2D
var shadow: Polygon2D


func setup(texture: Texture2D, footprint := Vector2(40, 16)) -> void:
	z_index = 0
	y_sort_enabled = true
	shadow = Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.40)
	shadow.z_index = 0
	shadow.z_as_relative = true
	shadow.show_behind_parent = true
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * footprint.x, sin(a) * footprint.y))
	shadow.polygon = pts
	add_child(shadow)

	if texture == null:
		return
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = Vector2(-texture.get_width() * 0.5, -float(texture.get_height()))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = 0
	add_child(sprite)
