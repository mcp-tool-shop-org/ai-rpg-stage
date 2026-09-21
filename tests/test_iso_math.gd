## test_iso_math.gd — 2:1 dimetric conversion is invertible and cell-stable.
extends RefCounted

const IsoMath := preload("res://stage/iso/iso_math.gd")


func run(t: RefCounted) -> void:
	t.equals(IsoMath.TILE_H * 2, IsoMath.TILE_W, "tile is 2:1 dimetric")

	var cart := Vector2(3, 1)
	var iso: Vector2 = IsoMath.cart_to_iso(cart)
	var back: Vector2 = IsoMath.iso_to_cart(iso)
	t.check(back.distance_to(cart) < 0.001, "cart → iso → cart round-trips")

	var cell := Vector2i(4, 2)
	var world: Vector2 = IsoMath.cell_to_world(cell)
	var cell_back: Vector2i = IsoMath.world_to_cell(world)
	t.equals(cell_back, cell, "cell → world → cell round-trips")

	# A step east in Cartesian must not be a step east on screen.
	var east: Vector2 = IsoMath.cart_to_iso(Vector2.RIGHT)
	t.check(abs(east.x) > 0.01 and abs(east.y) > 0.01,
		"Cartesian east is a diagonal on the diamond")

	var c := Vector2i(3, 1)
	var centre: Vector2 = IsoMath.cell_to_world(c)
	t.is_true(IsoMath.diamond_contains(centre, c), "cell centre is inside its diamond")
	t.is_false(IsoMath.diamond_contains(centre + Vector2(200, 0), c),
		"a point a tile away is outside the diamond")
	t.equals(IsoMath.pick_cell(centre), c, "pick_cell at centre returns that cell")
