## iso_math.gd — dimetric 2:1. Not true 120° isometry.
##
## Game isometric (Baldur's Gate, Diablo, almost every "iso" title) is a
## 2:1 pixel diamond: tile height is half the width, ~26.565°. Cartesian
## simulation space stays square. This file is the only place that conversion
## lives, so a TileMapLayer and an actor cannot disagree about where a cell is.
extends RefCounted

const TILE_W := 256
const TILE_H := 128


## Screen vector for a Cartesian step. Matches Godot 4 docs:
## iso.x = cart.x - cart.y ; iso.y = (cart.x + cart.y) * 0.5
static func cart_to_iso(cart: Vector2) -> Vector2:
	return Vector2(cart.x - cart.y, (cart.x + cart.y) * 0.5)


static func iso_to_cart(iso: Vector2) -> Vector2:
	return Vector2(iso.y + iso.x * 0.5, iso.y - iso.x * 0.5)


## World-pixel position of the CENTRE of a diamond cell, diamond-down layout.
## Matches Godot 4 TileMapLayer.map_to_local (origin is the bounding-box
## top-left, so the centre is offset by half a tile).
static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x - cell.y) * float(TILE_W) * 0.5 + float(TILE_W) * 0.5,
		float(cell.x + cell.y) * float(TILE_H) * 0.5 + float(TILE_H) * 0.5,
	)


static func world_to_cell(world: Vector2) -> Vector2i:
	var cx := world.x / (float(TILE_W) * 0.5) - 1.0
	var cy := world.y / (float(TILE_H) * 0.5) - 1.0
	return Vector2i(roundi((cy + cx) / 2.0), roundi((cy - cx) / 2.0))


## Point-in-diamond. `local_to_map` is rectangle-bounded on isometric tiles
## (godot #89423); click picking must use this, then take the highest-Y hit.
static func diamond_contains(world: Vector2, cell: Vector2i) -> bool:
	var c := cell_to_world(cell)
	var dx := absf(world.x - c.x) / (float(TILE_W) * 0.5)
	var dy := absf(world.y - c.y) / (float(TILE_H) * 0.5)
	return dx + dy <= 1.0


static func pick_cell(world: Vector2) -> Vector2i:
	var approx := world_to_cell(world)
	var best := approx
	var best_y := -INF
	var hit := false
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var cand := approx + Vector2i(ox, oy)
			if diamond_contains(world, cand):
				var wy := cell_to_world(cand).y
				if (not hit) or wy >= best_y:
					best_y = wy
					best = cand
					hit = true
	return best
