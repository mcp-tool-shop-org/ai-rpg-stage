## iso_actor.gd — a Foundry HD sprite planted on the dimetric ground.
##
## Blob is a Y-sort sibling at the actor's own z_index, drawn first
## (`show_behind_parent` is the Godot 4.x fix; there is no Node2D.y_sort_origin).
## Never z_index -1: that puts the shadow under an opaque dirt tile.
extends Node2D

const SpriteBinder := preload("res://stage/sprite_binder.gd")
const IsoMath := preload("res://stage/iso/iso_math.gd")

const HEIGHT_IN_TILES := 1.0

var character := ""
var sprite: Sprite2D
var shadow: Polygon2D


func setup(character_id: String) -> void:
	character = character_id
	z_index = 0
	y_sort_enabled = true

	shadow = Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.z_index = 0
	shadow.z_as_relative = true
	shadow.show_behind_parent = true
	var rx := 36.0
	var ry := 14.0
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	shadow.polygon = pts
	add_child(shadow)

	sprite = SpriteBinder.attach(self, character_id, HEIGHT_IN_TILES * float(IsoMath.TILE_H) / float(SpriteBinder.PACK_TILE_SIZE))
	if sprite:
		sprite.z_as_relative = true
		sprite.z_index = 0
		sprite.show_behind_parent = false


func face(motion: Vector2) -> void:
	if sprite:
		SpriteBinder.face(sprite, motion)


func face_named(bucket: String) -> void:
	if sprite:
		SpriteBinder.face_named(sprite, bucket)
