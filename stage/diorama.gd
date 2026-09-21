## diorama.gd — the reference diorama: Salt Road, standing up.
##
## Assembles the exported scene, the light rig, the dressing sets and the cast into one
## thing a person can look at. This is C4's deliverable in the sense that matters: not
## "the pipeline works" but "here is a place".
##
## WHAT IS AUTHORED ELSEWHERE AND ONLY BOUND HERE. The zones, their prose, the gate and
## its reason, the tiles and the props all come out of World Forge. This file adds
## exactly what the charter says the CLIENT owns — coordinates, light, dressing variants,
## camera — and nothing else. If something here looks like a rule, it is in the wrong
## file.
##
## THE CAST, and its honest state. The characters are the studio's own shipped
## `@sprite-foundry/townsfolk-hd` pack, consumed here for the first time by anything
## inside the studio. The pack is a generic fantasy VILLAGE roster and Salt Road is a
## mercantile harbour, so the casting is one good fit and four compromises — recorded per
## character below rather than smoothed over. The writing is Director-frozen; the sprites
## bend to it, not the reverse.
extends Node2D

const LightRig := preload("res://stage/light_rig.gd")
const Dressing := preload("res://stage/dressing.gd")
const SpriteBinder := preload("res://stage/sprite_binder.gd")
const SceneJoin := preload("res://client/scene_join.gd")
const FloorPainter := preload("res://stage/floor_painter.gd")

const IsoWorld := preload("res://stage/iso/iso_world.gd")

const WORLD_SCENE := "res://fixtures/world.tscn"
const PACK_JSON := "res://fixtures/pack.json"

## 512px HD sprites. Map-token scale (0.125) made them ants on a strategy atlas.
## Room view fills the screen with one zone; this is "a person standing in a room"
## — about 40% of a 160px-tall interior, which is the 2.5D read.
const CHARACTER_SCALE := 0.125

## Where the cast stands, and WHO each one is.
##
## `fit` is not decoration. It records how well the shipped pack served the writing, so
## the gap is legible to whoever next orders sprites from the production line — this is
## the first concrete character order any authored world has put to it.
const CAST := [
	{
		"id": "npc-corvane", "character": "elder", "zone": "weighing-floor",
		"offset": Vector2(96, 128),
		"fit": "townsfolk-hd elder — Assay Master Corvane",
		"pack_source": "elder",
	},
	{
		"id": "npc-halle", "character": "scribe", "zone": "bonded-warehouse",
		"offset": Vector2(64, 112),
		"fit": "townsfolk-hd scribe — Bonded Clerk Halle at the register",
		"pack_source": "scribe",
	},
	{
		"id": "npc-drell", "character": "guard", "zone": "customs-shed",
		"offset": Vector2(72, 104),
		"fit": "townsfolk-hd guard — Inspector Drell",
		"pack_source": "guard",
	},
	{
		"id": "npc-tally-boy", "character": "child", "zone": "long-quay",
		"offset": Vector2(240, 120),
		"fit": "townsfolk-hd child — the tally-boy",
		"pack_source": "child",
	},
	{
		"id": "npc-stair-collector", "character": "fisherman", "zone": "crooked-stair",
		"offset": Vector2(80, 128),
		"fit": "townsfolk-hd fisherman — dockside collector",
		"pack_source": "fisherman",
	},
]

## The player: the harbour factor. townsfolk-hd merchant, 4-layer 2.5D pack.
const PLAYER_CHARACTER := "merchant"
const PLAYER_START_ZONE := "counting-house"

var world: Node2D
var rig: Node2D
var dressing: Node
var join: RefCounted
var painter: Node2D
var player: Node2D
var pack: Dictionary = {}
var room: CanvasLayer
var iso: Node2D

## zone id -> the local lights belonging to it, so a re-dress can touch a zone's lamps
## without walking the whole tree.
var _zone_lights: Dictionary = {}


func _ready() -> void:
	build()


## Stand the whole thing up. Separate from `_ready` so a headless test can build it
## without running a scene, which is what makes the diorama testable at all.
##
## IDEMPOTENT, and it has to be: `_ready` calls it on tree entry, so a test that also
## calls it explicitly would otherwise build a SECOND world beside the first — Godot
## renames the duplicate child rather than complaining, so the symptom is a scene with
## two of everything and a joiner that resolves to whichever it indexed last.
func build() -> void:
	if world != null:
		return
	pack = _read_json(PACK_JSON)

	world = _instantiate_world()
	if world == null:
		push_error("diorama: could not load %s" % WORLD_SCENE)
		return
	world.name = "World"
	add_child(world)

	join = SceneJoin.new()
	join.call("index", world)

	rig = LightRig.new()
	rig.name = "LightRig"
	add_child(rig)
	rig.call("build")

	dressing = Dressing.new()
	dressing.name = "Dressing"
	add_child(dressing)

	# Paint the floors and the props FIRST, so the dressing sets group real visuals
	# rather than the metadata-only nodes the export ships.
	painter = FloorPainter.new()
	painter.name = "FloorPainter"
	add_child(painter)
	painter.call(
		"paint",
		pack.get("zoneIds", []),
		Callable(self, "zone_node"),
		Callable(self, "_biome_of"),
	)

	_build_dressing_sets()
	_build_zone_lights()
	_populate_cast()
	_place_player()
	_frame_camera()

	# Fourth-wall interiors stay in the tree for later, but they are not the play
	# camera. Play is dimetric: one harbour, Y-sorted, Foundry actors on a 2:1 grid.
	if world:
		world.visible = false
	iso = IsoWorld.new()
	iso.name = "IsoHarbour"
	add_child(iso)
	iso.call("build", pack, PLAYER_CHARACTER, CAST)
	var old_cam := get_node_or_null("DioramaCamera") as Camera2D
	if old_cam:
		old_cam.enabled = false

	# Open on the authored descriptor of the zone the player starts in, so the diorama's
	# first frame is a real state rather than a default.
	apply_zone_state(PLAYER_START_ZONE, [])


## Apply a zone's descriptor + variant tags. The single entry point a wire event uses,
## so a live re-dress and the opening frame cannot take different paths.
func apply_zone_state(zone_id: String, variant_tags: Array) -> void:
	var scene: Dictionary = _scene_of(zone_id)
	rig.call("apply_descriptor", scene, variant_tags)
	dressing.call("apply", variant_tags, zone_node(zone_id))
	_apply_lights_for(zone_id, variant_tags)


func zone_node(zone_id: String) -> Node:
	return join.call("zone_node", zone_id) as Node


## The authored prose for a zone, read off the SCENE.
##
## Zone descriptions are dropped at intake as `no-runtime-field` — the sim has nowhere to
## put them — and stamped into the .tscn as `metadata/description` instead. So the
## writing lives on the stage, which is where the charter puts presentation. This is the
## accessor that makes it usable.
func description_of(zone_id: String) -> String:
	var n := zone_node(zone_id)
	if n == null or not n.has_meta("description"):
		return ""
	return String(n.get_meta("description"))


## The gate text on a zone, if any. Read for DISPLAY only — the stage submits the move
## and renders the sim's refusal. There is deliberately no `can_enter()` here.
func gate_text_of(zone_id: String) -> String:
	var n := zone_node(zone_id)
	if n == null or not n.has_meta("entry_gate_reason"):
		return ""
	return String(n.get_meta("entry_gate_reason"))


# ── Assembly ──────────────────────────────────────────────────

func _instantiate_world() -> Node2D:
	if not ResourceLoader.exists(WORLD_SCENE):
		return null
	var packed: Variant = load(WORLD_SCENE)
	if not packed is PackedScene:
		return null
	return (packed as PackedScene).instantiate() as Node2D


## Create the swap-sets a re-dress toggles.
##
## Built per zone from the props the export already placed, so a variant is a REAL
## alternative view of the same place rather than a second copy of it. Rubble is added as
## new nodes because rubble is not a state a crate can be in; the crate itself is hidden
## in the same swap, which is the "same layout, different dressing" rule holding.
func _build_dressing_sets() -> void:
	for zone_id: Variant in (pack.get("zoneIds", []) as Array):
		var zn := zone_node(String(zone_id))
		if zn == null:
			continue

		# Intact dressing: whatever the exporter placed. Grouped, not created.
		for child: Node in zn.get_children():
			if child.name == "Props":
				for prop: Node in child.get_children():
					dressing.call("register", prop, "dressing:intact")

		# The damaged view: rubble where the props were.
		# The CONTAINER stays visible; the chunks inside it carry the state. Hiding the
		# container instead makes every chunk invisible no matter what its own flag says —
		# and `.visible` on a child still reports true, so a test that checks the flag
		# rather than `is_visible_in_tree()` passes over an invisible scene. Both halves of
		# that mistake were made here and are corrected together.
		var rubble := Node2D.new()
		rubble.name = "Rubble"
		zn.add_child(rubble)
		for i in range(3):
			var chunk := Polygon2D.new()
			chunk.name = "Chunk%d" % i
			# Deliberately crude, deliberately deterministic — no RNG, so two runs of the
			# same session look identical, which P4 has to prove.
			var s := 14.0 + i * 5.0
			chunk.polygon = PackedVector2Array([
				Vector2(-s, s), Vector2(-s * 0.4, -s * 0.6), Vector2(s * 0.7, -s * 0.2), Vector2(s, s),
			])
			chunk.color = Color(0.31, 0.29, 0.27)
			chunk.position = Vector2(48 + i * 62, 96 + (i % 2) * 34)
			chunk.visible = false
			rubble.add_child(chunk)
			dressing.call("register", chunk, "props:rubble")

		# The occupied view: a checkpoint across the way in.
		var checkpoint := Polygon2D.new()
		checkpoint.name = "Checkpoint"
		checkpoint.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(96, 0), Vector2(96, 12), Vector2(0, 12),
		])
		checkpoint.color = Color(0.55, 0.42, 0.20)
		checkpoint.position = Vector2(24, 140)
		checkpoint.visible = false
		zn.add_child(checkpoint)
		dressing.call("register", checkpoint, "props:checkpoint")


## A lamp per zone, warm and low, positioned from the zone's own rectangle.
func _build_zone_lights() -> void:
	for zone_id: Variant in (pack.get("zoneIds", []) as Array):
		var id := String(zone_id)
		var zn := zone_node(id) as Node2D
		if zn == null:
			continue
		var lamp: Node = rig.call(
			"add_point_light",
			zn.position + Vector2(72, 72),
			190.0,
			Color(1.0, 0.86, 0.62),
			0.55,
		)
		_zone_lights[id] = [lamp]


## Local lights dim with the zone's condition. A damaged quay is not just greyer
## overall — its own lamps are out, which is what makes the change read as damage rather
## than as weather.
func _apply_lights_for(zone_id: String, variant_tags: Array) -> void:
	var dim := false
	for t: Variant in variant_tags:
		if String(t) == "lighting:dim":
			dim = true
	for lamp: Variant in (_zone_lights.get(zone_id, []) as Array):
		if lamp is PointLight2D:
			(lamp as PointLight2D).energy = 0.16 if dim else 0.55

	# The zone's own floor darkens too. The global ambient belongs to wherever the PLAYER
	# is standing — in a real game one zone fills the screen, so that is correct — but a
	# diorama shows six at once, and a shocked quay has to read as damaged from across the
	# harbour rather than only when the camera is in it.
	var zn := zone_node(zone_id) as Node2D
	if zn == null:
		return
	var floor_node := zn.get_node_or_null("Floor") as Polygon2D
	if floor_node != null:
		floor_node.modulate = Color(0.55, 0.55, 0.62) if dim else Color.WHITE


func _populate_cast() -> void:
	for member: Dictionary in CAST:
		var zn := zone_node(String(member["zone"])) as Node2D
		if zn == null:
			continue
		var holder := Node2D.new()
		holder.name = String(member["id"])
		holder.position = member["offset"]
		holder.set_meta("entity_id", member["id"])
		holder.set_meta("pack_source", member["pack_source"])
		holder.set_meta("casting_fit", member["fit"])
		zn.add_child(holder)
		SpriteBinder.attach(holder, String(member["character"]), CHARACTER_SCALE)


func _place_player() -> void:
	var zn := zone_node(PLAYER_START_ZONE) as Node2D
	if zn == null:
		return
	player = Node2D.new()
	player.name = "Player"
	player.position = Vector2(112, 136)
	player.set_meta("entity_id", "player")
	zn.add_child(player)
	SpriteBinder.attach(player, PLAYER_CHARACTER, CHARACTER_SCALE)


## Frame every zone. Computed from the scene rather than authored, so a world with more
## zones does not need a camera edit.
##
## Also lays the backdrop, because the two need the same bounds. The first render put six
## lit rooms on flat viewport grey, which read as a debug view no matter how well the
## rooms themselves were lit — the space BETWEEN zones was doing nothing, and in a harbour
## the space between things is water.
func _frame_camera() -> void:
	var cam := Camera2D.new()
	cam.name = "DioramaCamera"
	var bounds := Rect2()
	var first := true
	for zone_id: Variant in (pack.get("zoneIds", []) as Array):
		var zn := zone_node(String(zone_id)) as Node2D
		if zn == null:
			continue
		var extent: Vector2 = FloorPainter.zone_extent(zn)
		if extent == Vector2.ZERO:
			extent = Vector2(320, 224)
		var r := Rect2(zn.position, extent)
		bounds = r if first else bounds.merge(r)
		first = false
	# Water under everything, generously oversized so no camera position shows its edge.
	var water := Polygon2D.new()
	water.name = "Harbour"
	var pad := 900.0
	var tl := bounds.position - Vector2(pad, pad)
	var br := bounds.end + Vector2(pad, pad)
	water.polygon = PackedVector2Array([
		tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y),
	])
	water.color = Color(0.11, 0.16, 0.19)
	water.z_index = -60
	water.z_as_relative = false
	add_child(water)
	move_child(water, 0)

	cam.position = bounds.get_center()
	add_child(cam)
	# The export also ships a Camera2D aimed at the harbour centroid. If that
	# one stays enabled, Godot renders THE ATLAS and this camera's zoom is a
	# lie the tests can pass while the player still sees postage stamps.
	_disable_export_cameras()
	look_at_zone(PLAYER_START_ZONE)


## One room. Not a village map. Not six floating carpets.
##
## Salt Road is a ZONE GRAPH — counting house, quay, warehouse, stair — authored
## as separate rectangles with gaps. Drawing them all at once is a debug view of
## the graph. Play is: you are in this room; walking submits a move; the next
## room replaces this one.
func look_at_zone(zone_id: String) -> void:
	var cam := camera()
	var zn := zone_node(zone_id) as Node2D
	if cam == null or zn == null:
		return
	_disable_export_cameras()
	# The 19-tile "ground" layer is leftover atlas dressing. It is not a street.
	var ground := world.get_node_or_null("Ground") if world else null
	if ground:
		ground.visible = false
	var extent: Vector2 = FloorPainter.zone_extent(zn)
	if extent == Vector2.ZERO:
		extent = Vector2(192, 160)
	if iso:
		var from := String(iso.get("current_zone"))
		if from.is_empty():
			from = PLAYER_START_ZONE
		var motion: Vector2 = iso.call("world_pos_of", zone_id) - iso.call("world_pos_of", from)
		iso.call("walk_player_to", zone_id, motion)
		return
	cam.enabled = true
	cam.make_current()
	cam.global_position = zn.global_position + extent * 0.5
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 8.0 or vp.y < 8.0:
		vp = Vector2(1280, 720)
	var margin := 1.06
	var zx := vp.x / (extent.x * margin)
	var zy := (vp.y * 0.70) / (extent.y * margin)
	var z := clampf(minf(zx, zy), 3.5, 14.0)
	cam.zoom = Vector2(z, z)


func _disable_export_cameras() -> void:
	if world == null:
		return
	for node: Node in world.find_children("*", "Camera2D", true, false):
		var export_cam := node as Camera2D
		if export_cam:
			export_cam.enabled = false


func camera() -> Camera2D:
	if iso:
		var iso_cam := iso.get_node_or_null("IsoCamera") as Camera2D
		if iso_cam:
			return iso_cam
	return get_node_or_null("DioramaCamera") as Camera2D


## The biome key for a zone, for the floor painter. A separate accessor so the painter
## never reads the pack — it is handed the descriptor, exactly as the light rig is.
func _biome_of(zone_id: String) -> String:
	return String(_scene_of(zone_id).get("biome", ""))


func _scene_of(zone_id: String) -> Dictionary:
	for z: Variant in (pack.get("zones", []) as Array):
		var zd: Dictionary = z as Dictionary
		if String(zd.get("id", "")) == zone_id:
			# The fixture publishes the authored descriptor keys; the wire supplies the
			# derived ones at runtime.
			return {
				"timeOfDay": zd.get("timeOfDay", "morning"),
				"biome": zd.get("biome", ""),
			}
	return {}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
