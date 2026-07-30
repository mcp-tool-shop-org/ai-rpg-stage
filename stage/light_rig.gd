## light_rig.gd — the diorama's light, driven by the sim's descriptor keys.
##
## Sea of Stars is the reference tier and it reaches it in PURE 2D under a real dynamic
## light rig — Sabotage spent its first six months on exactly that look-dev before any
## content. Godot 4 carries the same capability natively: `CanvasModulate` for ambient,
## `DirectionalLight2D` for a sun, `PointLight2D` for local sources, and normal maps on
## `CanvasTexture` so a painterly sprite takes the light instead of sitting on top of
## it. None of it needs a 3D scene, which is why literal HD-2D (billboards in full 3D)
## is a different and much more expensive target — Cassette Beasts, the flagship Godot
## 2.5D game, calls performance its biggest consistent technical problem.
##
## WHAT THE SIM SENDS, AND WHAT THIS DOES WITH IT.
##
## The sim owes a DESCRIPTOR, never a layout (Takahashi/Miyauchi 2018; Triangle
## Strategy's rule that state flags swap lighting and dressing variants and never
## geometry). What actually arrives, measured from the engine's own vocabulary:
##
##   scene.timeOfDay        'morning' | 'dusk' | 'night' | …  — authored
##   scene.biome            'harbour-stone' | …               — authored
##   scene.dressingDensity  sparse | normal | dense           — derived from prop count
##   variantTags            dressing:<condition>, lighting:dim,
##                          props:rubble | checkpoint | sparse — DERIVED from state
##
## Nothing in that list is a colour, an intensity or an asset path, and that is
## deliberate: the vocabulary has nothing in it a renderer could read as geometry. The
## mapping from key to light is entirely THIS side's business, which is what makes it a
## taste surface the sim cannot accidentally overwrite.
extends Node2D

## Ambient colour per time-of-day key. The stage's own art decisions — the sim never
## sends a colour and must not.
const TIME_OF_DAY_AMBIENT := {
	"dawn": Color(0.52, 0.48, 0.56),
	"morning": Color(0.78, 0.79, 0.82),
	"day": Color(0.94, 0.94, 0.92),
	"dusk": Color(0.56, 0.44, 0.42),
	"night": Color(0.22, 0.27, 0.40),
}

## Sun angle and warmth per time-of-day key. Morning light on a harbour comes in low
## and from the water.
const TIME_OF_DAY_SUN := {
	"dawn": {"rotation": -20.0, "color": Color(1.0, 0.84, 0.68), "energy": 0.22},
	"morning": {"rotation": -35.0, "color": Color(1.0, 0.95, 0.86), "energy": 0.30},
	"day": {"rotation": -75.0, "color": Color(1.0, 1.0, 0.96), "energy": 0.34},
	"dusk": {"rotation": -12.0, "color": Color(1.0, 0.70, 0.50), "energy": 0.26},
	"night": {"rotation": -60.0, "color": Color(0.50, 0.62, 1.0), "energy": 0.12},
}

## `lighting:dim` is the one lighting key the SIM derives — from a zone's condition, not
## from the clock. A damaged quay is a darker quay, and this is the multiplier that says
## so without the sim ever naming a colour.
const DIM_FACTOR := 0.62

var ambient: CanvasModulate
var sun: DirectionalLight2D

var _time_of_day := "morning"
var _dim := false


func _ready() -> void:
	if ambient == null:
		ambient = get_node_or_null("Ambient") as CanvasModulate
	if sun == null:
		sun = get_node_or_null("Sun") as DirectionalLight2D
	_apply()


## Build the rig in code, so a scene file cannot drift from what this script expects.
##
## The alternative — nodes in the .tscn, looked up by name — is how a renamed node
## becomes a silent null and a rig that quietly does nothing.
func build() -> void:
	ambient = CanvasModulate.new()
	ambient.name = "Ambient"
	add_child(ambient)

	sun = DirectionalLight2D.new()
	sun.name = "Sun"
	# Shadows on, so a LightOccluder2D on a crate or a crane actually casts. Without
	# this the rig lights but nothing occludes, which reads as flat no matter how the
	# colours are tuned.
	sun.shadow_enabled = true
	sun.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(sun)

	_apply()


## Apply a zone's scene descriptor. Unknown keys fall back rather than fail — tolerant
## OUT (RFC 9413): the sim may learn to say `overcast` before the stage knows the word,
## and a client that crashed on an unrecognised descriptor would make adding one a
## breaking change.
func apply_descriptor(scene: Dictionary, variant_tags: Array = []) -> void:
	var tod := String(scene.get("timeOfDay", ""))
	if TIME_OF_DAY_AMBIENT.has(tod):
		_time_of_day = tod

	_dim = false
	for tag: Variant in variant_tags:
		if String(tag) == "lighting:dim":
			_dim = true

	_apply()


func time_of_day() -> String:
	return _time_of_day


func is_dim() -> bool:
	return _dim


## The colour the ambient node actually carries. Read back from the NODE rather than
## recomputed, so a test cannot pass by agreeing with the same arithmetic twice.
func ambient_color() -> Color:
	return ambient.color if ambient != null else Color.WHITE


func _apply() -> void:
	var base: Color = TIME_OF_DAY_AMBIENT.get(_time_of_day, Color.WHITE)
	if _dim:
		base = Color(base.r * DIM_FACTOR, base.g * DIM_FACTOR, base.b * DIM_FACTOR, base.a)
	if ambient != null:
		ambient.color = base

	if sun != null:
		var cfg: Dictionary = TIME_OF_DAY_SUN.get(_time_of_day, TIME_OF_DAY_SUN["day"])
		sun.rotation_degrees = float(cfg["rotation"])
		sun.color = cfg["color"]
		sun.energy = float(cfg["energy"]) * (DIM_FACTOR if _dim else 1.0)


## Add a local light — a lamp, a brazier, a lit window.
##
## `PointLight2D` needs a texture to define its falloff; Godot draws nothing from a
## textureless one, which is a silent no-op and an easy hour to lose. A radial gradient
## is generated here so the rig has no external art dependency for something that is
## pure maths.
func add_point_light(at: Vector2, radius: float, color: Color, energy := 1.0) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = _falloff_texture()
	light.position = at
	light.color = color
	light.energy = energy
	# The gradient is authored at 256px; scale it to the radius the caller asked for.
	light.texture_scale = radius / 128.0
	light.shadow_enabled = true
	add_child(light)
	return light


static func _falloff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex
