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

const WORLD_SCENE := "res://fixtures/world.tscn"
const PACK_JSON := "res://fixtures/pack.json"

## 512px sprites in a 48px-tile world → a person 2.5 tiles tall (120px).
##
## RESEARCHED, not picked (2026-07-30): 48–64px is the painterly (non-pixel-art) tile
## band, and characters in that band stand 2–3 tiles tall.
## https://freegamesprites.com/en/news/tile-size-2d-game-pixel-art-guide
##
## Was 0.125 against a 32px tile, which is a PIXEL-ART tile size — too small to carry
## painted detail, and the reason the rooms read as closets. The tile size and this
## number move together; changing one alone breaks the convention that sets both.
const CHARACTER_SCALE := 0.234

## Where the cast stands, and WHO each one is.
##
## `fit` is not decoration. It records how well the shipped pack served the writing, so
## the gap is legible to whoever next orders sprites from the production line — this is
## the first concrete character order any authored world has put to it.
const CAST := [
	{
		"id": "npc-corvane", "character": "corvane", "zone": "weighing-floor",
		"at": Vector2(0.30, 0.55),
		"fit": "good — an old man who wants to retire without signing a false weight",
		"pack_source": "elder",
	},
	{
		"id": "npc-halle", "character": "halle", "zone": "bonded-warehouse",
		"at": Vector2(0.62, 0.42),
		"fit": "COMPROMISE — right period and register, but she is holding herbs, not a register",
		"pack_source": "herbalist",
	},
	{
		"id": "npc-drell", "character": "drell", "zone": "customs-shed",
		"at": Vector2(0.45, 0.66),
		"fit": "acceptable — reads as officialdom, which is most of Drell",
		"pack_source": "noble",
	},
	{
		"id": "npc-tally-boy", "character": "tally-boy", "zone": "long-quay",
		"at": Vector2(0.55, 0.50),
		"fit": "good — he is a boy with bad news",
		"pack_source": "child",
	},
	{
		"id": "npc-stair-collector", "character": "collector", "zone": "crooked-stair",
		"at": Vector2(0.38, 0.60),
		"fit": "acceptable — a hard dockside figure; nothing in the pack collects debts",
		"pack_source": "fisherman",
	},
]

## The player: a factor. The one casting the pack got exactly right.
const PLAYER_CHARACTER := "factor"
const PLAYER_START_ZONE := "counting-house"

var world: Node2D
var rig: Node2D
var dressing: Node
var join: RefCounted
var painter: Node2D
var player: Node2D
var pack: Dictionary = {}

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
			zn.position + FloorPainter.zone_extent(zn) * 0.5,
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
		# Proportional to the ROOM, not absolute pixels. Absolute offsets were tuned
		# against 6x5-tile closets and left the whole cast huddled in one corner the
		# moment the sandbox grew — a position that only reads correctly at one world
		# size is a constant pretending to be a placement.
		holder.position = FloorPainter.zone_extent(zn) * (member["at"] as Vector2)
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
	player.position = FloorPainter.zone_extent(zn) * 0.5
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
	# Zoom is DERIVED from the bounds, not authored. It was hardcoded at 0.72, tuned by
	# eye against a 40×28-tile world; when the sandbox grew to 120×84 at 48px the same
	# number framed one corner of the quay and the diorama looked broken rather than
	# bigger. A view that only works at one world size is a constant pretending to be a
	# camera.
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0 and bounds.size.x > 0.0 and bounds.size.y > 0.0:
		var margin := 1.12  # water around the town, so nothing sits on the frame edge
		var fit: float = minf(vp.x / (bounds.size.x * margin), vp.y / (bounds.size.y * margin))
		cam.zoom = Vector2(fit, fit)
	else:
		cam.zoom = Vector2(0.72, 0.72)
	add_child(cam)
	# ⚠ MAKE IT CURRENT, EXPLICITLY. The exported world.tscn ships its own Camera2D
	# (the authoring view), and it enters the tree first — so it, not this one, was the
	# active camera for every render since P3. That was invisible while the world was
	# small enough for the export camera's default zoom to frame it by luck, and it
	# turned every shot into a corner crop the moment the sandbox grew. A camera that is
	# built, positioned, zoomed, and never made current is a camera that does nothing.
	cam.make_current()


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
