## sprite_binder.gd — bind a Sprite Foundry HD character to a node, and face it.
##
## The studio's `-hd` packs shipped 2026-07-01 and had no consumer inside the studio.
## This is the consumer. The pack contract (`townsfolk-hd/pack.json`, read rather than
## assumed):
##
##   tileSize      512
##   pivot         [0.5, 1]  — bottom-centre, so a character stands ON a point
##   directions    front, front_left, left, back_left, back, back_right, right, front_right
##   layers        albedo, normal, mask, depth
##   maskChannels  r=ao  g=roughness  b=emissive
##
## TWO THINGS THIS FILE EXISTS FOR:
##
## 1. **The normal map reaches the light rig.** Godot's `CanvasTexture` carries a
##    `normal_texture`, and a 2D light striking it shades the sprite as though it had
##    surface relief. That is what makes a painterly sprite sit inside a lit scene
##    instead of on top of it, and it is the reason these packs ship a normal layer at
##    all. Binding only the albedo would waste half of what the production line
##    produced.
##
## 2. **Direction is DERIVED, never authored.** The sim sends movement; it does not send
##    a facing, and it should not — a facing is presentation. The bucketing lives here,
##    with the pack's own direction order as its single source of truth.
extends RefCounted

## The pack's direction order, verbatim. Index 0 is `front` and the list runs
## counter-clockwise in screen space. Deriving a bucket from this array rather than
## hard-coding eight names means a pack that reorders them stays correct.
const DIRECTIONS := [
	"front", "front_left", "left", "back_left",
	"back", "back_right", "right", "front_right",
]

const PACK_TILE_SIZE := 512
## `pivot: [0.5, 1]` from the manifest — bottom-centre.
const PACK_PIVOT := Vector2(0.5, 1.0)

const CHARACTER_ROOT := "res://assets/characters"


## Which of the eight sprites faces a given direction of travel.
##
## Screen space: +x right, +y DOWN. So a vector pointing down is `front` (toward the
## camera) and one pointing up is `back`.
##
## THE MATHS, and the mistake worth recording because it is invisible by eye.
##
## Walk the pack's list in screen coordinates: front is (0,+1) pointing DOWN,
## front_left is (-1,+1), left is (-1,0), back_left is (-1,-1), back is (0,-1). With +y
## down, that sequence rotates CLOCKWISE on screen — so `atan2(y, x)` already increases
## in the list's own direction and needs no flip.
##
## The first version negated y ("so angles increase counter-clockwise the way the
## direction list does"), which MIRRORED the horizontal axis: front and back were right,
## and every left/right was swapped. That is exactly the failure the eight-point test was
## written for — a character facing the wrong way looks deliberate, so nothing about the
## scene would have looked broken.
##
## `- 90` puts `front` at bucket 0; rounding to the nearest of eight 45° sectors gives
## the index; the modulo handles the negative half of atan2's range.
static func direction_for(motion: Vector2) -> String:
	if motion.is_zero_approx():
		return "front"
	var degrees := rad_to_deg(atan2(motion.y, motion.x)) - 90.0
	var bucket := int(round(degrees / 45.0)) % DIRECTIONS.size()
	if bucket < 0:
		bucket += DIRECTIONS.size()
	return DIRECTIONS[bucket]


## Path to one sprite of one character.
static func sprite_path(character: String, layer: String, direction: String) -> String:
	return "%s/%s/%s/%s.png" % [CHARACTER_ROOT, character, layer, direction]


## Does this character have all eight facings, or only the one it stands in?
##
## Asked rather than assumed: the diorama vendors eight directions for the character
## that MOVES and a single facing for those that stand, so a caller that turned a
## standing NPC would otherwise silently get a missing texture.
static func has_all_directions(character: String) -> bool:
	for d: String in DIRECTIONS:
		if not ResourceLoader.exists(sprite_path(character, "albedo", d)):
			return false
	return true


## Build a `CanvasTexture` pairing albedo with its normal map.
##
## Returns null when the albedo is missing — a caller should know it asked for a
## character that is not vendored, rather than receive a blank sprite that looks like a
## rendering bug.
static func canvas_texture(character: String, direction: String) -> CanvasTexture:
	var albedo_path := sprite_path(character, "albedo", direction)
	if not ResourceLoader.exists(albedo_path):
		return null

	var tex := CanvasTexture.new()
	tex.diffuse_texture = load(albedo_path)

	# The normal map is optional per character but present for the whole vendored cast.
	# When absent the sprite still lights, just flatly.
	var normal_path := sprite_path(character, "normal", direction)
	if ResourceLoader.exists(normal_path):
		tex.normal_texture = load(normal_path)

	return tex


## Attach a character to a parent node as a `Sprite2D`, ready to be lit and faced.
##
## The offset applies the pack's bottom-centre pivot so the sprite's FEET land on the
## node's position. Without it a character floats half a body above the ground it is
## supposed to be standing on, at these sprite sizes by 256 pixels — visible, and the
## kind of thing that gets "fixed" by nudging a magic number instead of reading the
## manifest.
static func attach(parent: Node2D, character: String, scale_factor := 1.0) -> Sprite2D:
	var tex := canvas_texture(character, "front")
	if tex == null:
		return null

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.centered = false
	sprite.offset = Vector2(
		-PACK_TILE_SIZE * PACK_PIVOT.x,
		-PACK_TILE_SIZE * PACK_PIVOT.y,
	)
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.set_meta("character", character)
	sprite.set_meta("facing", "front")
	parent.add_child(sprite)
	return sprite


## Turn an attached sprite to face a direction of travel.
##
## A no-op for a character with only one vendored facing, rather than a broken texture:
## a standing NPC that cannot turn should keep looking the way it looks.
static func face(sprite: Sprite2D, motion: Vector2) -> String:
	var character := String(sprite.get_meta("character", ""))
	if character.is_empty():
		return ""
	var wanted := direction_for(motion)
	var tex := canvas_texture(character, wanted)
	if tex == null:
		return String(sprite.get_meta("facing", "front"))
	sprite.texture = tex
	sprite.set_meta("facing", wanted)
	return wanted
