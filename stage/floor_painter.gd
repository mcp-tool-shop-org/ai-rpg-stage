## floor_painter.gd — give the diorama a floor and something to look at.
##
## WHY THIS EXISTS, and it is a real finding rather than a decoration pass. The first
## render of the assembled diorama was a debug view: 52 tests green, and a screenshot
## showing six characters and nineteen scattered tiles floating on flat grey. The wiring
## was right and the scene was not a place.
##
## Three measured reasons, all of them "the export gives the client geometry, not art":
##
## 1. **Zones have no visual body.** A zone node carries position, description, light,
##    noise, elevation, district — and its EXTENT only as a `RectangleShape2D` on its
##    `Collision/CollisionShape2D`. Nothing paints a floor, because a floor is a look and
##    looks are client-owned (charter §4 Pillar 2).
##
## 2. **Props are metadata-only.** `export-godot` emits each placement as a bare `Node2D`
##    carrying `prop_def`, `display_name`, `walkable`, `interactable` — correct, since the
##    sim has no business shipping art, but it means a prop draws NOTHING until the client
##    decides what a "crate under seal" looks like.
##
## 3. **The authored tile layer is texture, not coverage.** Nineteen tiles across a
##    forty-tile map: the world authors the stretch of WET stone along the quay lip
##    because that stretch is load-bearing fiction, not a full floor.
##
## So this module paints what the client owns: a floor per zone from the zone's own
## extent, tinted by its biome key, and a shape per prop from its definition. Every
## colour here is a stage decision the simulation cannot see or override.
extends Node2D

## Floor tint per biome key. The sim sends `biome: 'harbour-stone'`; what that LOOKS like
## is entirely this side's business, which is the whole point of a descriptor.
const BIOME_FLOOR := {
	"harbour-stone": Color(0.30, 0.33, 0.36),
	"counting-house": Color(0.27, 0.21, 0.16),
	"bonded-store": Color(0.20, 0.18, 0.15),
	"customs": Color(0.24, 0.22, 0.20),
	"warren-brick": Color(0.17, 0.14, 0.13),
}
const FLOOR_FALLBACK := Color(0.34, 0.34, 0.36)

## Behind everything, including the authored tile layer at -10.
const FLOOR_Z := -40
const WALL_Z := -30

## What a prop looks like: size in pixels and a colour. The client's own table, because
## the definition ships dimensions in TILES and no appearance at all.
const PROP_LOOK := {
	# Desaturated on purpose. The first pass used saturated colours and the six scales
	# rendered as a row of bright yellow blocks — legible as data, not as brass on a
	# bench. A placeholder should read as an OBJECT that is not finished, not as UI.
	"prop-scales": {"size": Vector2(14, 20), "color": Color(0.47, 0.41, 0.26)},
	"prop-hawsers": {"size": Vector2(34, 14), "color": Color(0.40, 0.36, 0.28)},
	"prop-crate-sealed": {"size": Vector2(26, 24), "color": Color(0.35, 0.27, 0.18)},
	"prop-cage": {"size": Vector2(46, 44), "color": Color(0.23, 0.23, 0.26)},
	"prop-desk": {"size": Vector2(30, 20), "color": Color(0.31, 0.22, 0.15)},
	"prop-crane": {"size": Vector2(26, 78), "color": Color(0.28, 0.27, 0.25)},
}
const PROP_FALLBACK := {"size": Vector2(22, 22), "color": Color(0.55, 0.50, 0.45)}

var _painted_zones := 0
var _painted_props := 0


## Paint every zone the joiner resolved. `biome_of` is a Callable so this module never
## reads the pack itself — it is given the descriptor, exactly as the rig is.
func paint(zone_ids: Array, zone_node_of: Callable, biome_of: Callable) -> void:
	for id: Variant in zone_ids:
		var zn := zone_node_of.call(String(id)) as Node2D
		if zn == null:
			continue
		var extent := zone_extent(zn)
		if extent == Vector2.ZERO:
			continue
		_paint_floor(zn, extent, String(biome_of.call(String(id))))
		_painted_zones += 1
	_paint_props()


## A zone's size, read from its collision hull.
##
## The exporter puts a `RectangleShape2D` on `Collision/CollisionShape2D` covering the
## zone bounds — the only place the extent survives into the scene, since the zone node
## itself carries no width or height metadata. Returns ZERO when absent, so a caller skips
## rather than paints a zero-sized floor nobody can see and nobody can explain.
static func zone_extent(zone: Node2D) -> Vector2:
	var shape_node := zone.get_node_or_null("Collision/CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return Vector2.ZERO
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		return Vector2.ZERO
	return rect.size


func painted_zones() -> int:
	return _painted_zones


func painted_props() -> int:
	return _painted_props


func _paint_floor(zone: Node2D, extent: Vector2, biome: String) -> void:
	var tint: Color = BIOME_FLOOR.get(biome, FLOOR_FALLBACK)

	var floor_poly := Polygon2D.new()
	floor_poly.name = "Floor"
	floor_poly.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(extent.x, 0), extent, Vector2(0, extent.y),
	])
	floor_poly.color = tint
	floor_poly.z_index = FLOOR_Z
	floor_poly.z_as_relative = false
	zone.add_child(floor_poly)

	# A lip around the edge, so adjacent zones read as separate rooms rather than one
	# continuous wash of colour. Four thin quads instead of a Line2D because a closed
	# Line2D on an axis-aligned rect renders mitre artefacts at the corners.
	var edge := Color(tint.r * 0.62, tint.g * 0.62, tint.b * 0.62)
	var t := 3.0
	var bars := [
		[Vector2.ZERO, Vector2(extent.x, t)],
		[Vector2(0, extent.y - t), Vector2(extent.x, t)],
		[Vector2.ZERO, Vector2(t, extent.y)],
		[Vector2(extent.x - t, 0), Vector2(t, extent.y)],
	]
	for i in range(bars.size()):
		var at: Vector2 = bars[i][0]
		var size: Vector2 = bars[i][1]
		var bar := Polygon2D.new()
		bar.name = "Edge%d" % i
		bar.polygon = PackedVector2Array([
			at, at + Vector2(size.x, 0), at + size, at + Vector2(0, size.y),
		])
		bar.color = edge
		bar.z_index = WALL_Z
		bar.z_as_relative = false
		zone.add_child(bar)


## Draw the props the exporter placed as metadata-only nodes.
##
## Attached as CHILDREN of the export's own nodes, so the placement stays the export's
## decision and only the appearance is this module's. A prop the client has no look for
## still draws — as the fallback block — because an unrecognised prop that renders nothing
## is indistinguishable from a prop that was never placed.
func _paint_props() -> void:
	var root := get_parent()
	if root == null:
		return
	for node: Node in _all_descendants(root):
		if not node.has_meta("prop_def"):
			continue
		var def := String(node.get_meta("prop_def"))
		var look: Dictionary = PROP_LOOK.get(def, PROP_FALLBACK)
		var size: Vector2 = look["size"]

		var body := Polygon2D.new()
		body.name = "Look"
		# Bottom-centred like the characters, so a prop sits ON its point.
		body.polygon = PackedVector2Array([
			Vector2(-size.x * 0.5, -size.y), Vector2(size.x * 0.5, -size.y),
			Vector2(size.x * 0.5, 0), Vector2(-size.x * 0.5, 0),
		])
		body.color = look["color"]
		(node as Node).add_child(body)
		_painted_props += 1


static func _all_descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			out.append(c)
			stack.append(c)
	return out
