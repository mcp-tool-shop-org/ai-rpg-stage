---
title: The dimetric camera
description: 2:1 projection, Y-sort, 128 px strips, contact blobs, the ANDON, and the lie budget.
sidebar:
  order: 3
---

## The projection is a setting

Game "isometric" is **2:1 dimetric**: the diamond of one ground cell is twice as wide as it is tall,
256×128 px here, and its edges run at 26.565°. True 30° isometry is not what the kit uses and the ANDON
refuses it.

That angle is a camera setting, not an art direction note. Every plate in `assets/dimetric/` was rendered
by `assets/dimetric/camera/dimetric_60_45.py` under headless Blender:

| Knob | Value |
|---|---|
| Camera | orthographic, rotation X 60°, Y 0°, Z 45°, Sensor Fit horizontal |
| `ortho_scale` | `(N + M) / √2` for an N×M footprint (1.41421 per tile when square) |
| Resolution | `128·(N+M)` wide × `128·K` tall; the foot vertex sits on the bottom row |
| Alpha | Film Transparent, from the Combined pass. Never keyed, never matted |
| Light | one Sun, one azimuth, the same for every plate (`sun_euler_deg` in `MANIFEST.json`) |
| Scale | one Blender unit = one tile; a person is 128 px; a one-storey facade is 384 px (1 : 3) |

World +X projects to screen down-right, world +Y to screen up-right. A footprint's near vertex is world
`(N, 0, 0)`, which is what `TileMapLayer` DIAMOND_DOWN expects.

## The Godot side

`stage/iso/` is the kit:

- `iso_math.gd` — the only place Cartesian ↔ 2:1 conversion lives, so a `TileMapLayer` and an actor cannot
  disagree about where a cell is. Tested round-trip.
- `iso_world.gd` — one `TileMapLayer` (`TILE_SHAPE_ISOMETRIC`, `TILE_LAYOUT_DIAMOND_DOWN`, 256×128),
  Y-sorted, ground atlas built at load from the manifest's tiles (converted to RGBA8 before any blit), the
  structures and actors as siblings under one Y-sorted parent, click-to-cell, the follow camera.
- `iso_structure.gd` — a building plate cut into **128 px vertical strips**, each a 1×1 drawable owned by
  the front-edge cell beneath it, art hung upward with a texture origin. One drawable per diamond is the only
  order a painter's sort can honour; multi-cell tiles sort wrongly under Y-sort in Godot (#92682).
- `iso_actor.gd` — a Foundry HD sprite bound through `CanvasTexture` (albedo + normal), foot pivot, with a
  contact blob drawn `show_behind_parent` at the actor's own `z_index`. Not `z_index -1`: nodes only Y-sort
  against each other on the same z_index, so a negative index draws under the floor.
- `iso_prop.gd` — one-cell props with a foot origin.

Two Godot facts the code works around: `local_to_map()` is rectangle-bounded on isometric tiles, so
click-to-cell runs a diamond test after it; and moving the active `Camera2D` does not refresh the canvas
transform in the same frame, so `force_update_scroll()` is called before any pick during a walk.

The standing cells are not computed here: `iso_world.gd` takes each townsperson's cell, zone and facing —
and the anchor of every zone's 3×3 — from the `presentation` block World Forge authors onto
`fixtures/pack.json`, falling back to `fixtures/harbour-occupancy.json` and then to a derived corner cell
when the pack carries none.

## Lighting

One 2D canvas. Torches are `PointLight2D`s with a nonzero `height` (the light's Z in pixels), which is what
makes a Foundry normal map read at all. The cap is 16 lights per canvas item, compiled into the renderer, and
a two-light torch rig costs two of them; the harbour budgets accordingly. Directional 2D shadows are
infinitely long and `height` never shortens them, which is why the **blob** is the only height cue.

## The ANDON

`assets/dimetric/andon/iso_andon.py` runs on every PNG before it may enter `res://`. Exit 0 only when every
gate passes; the log JSON sits beside the file and `MANIFEST.json` is regenerated from those logs.

| Gate | Checks |
|---|---|
| 0 | decoded format is RGBA (an RGB plate is what emptied the ground atlas once) |
| 1 | opaque ratio: ground 0.35–0.62 · structure < 0.85 · prop < 0.70 |
| 2 | all four 8×8 corner blocks are alpha 0 |
| 3 | lowest-row slab edges fit 26.565° ± 1.5° |
| 4 | slab width = 128·(N+M) ± 4 px |
| 5 | used-rect centre X = image centre ± 2 px (the foot origin) |
| 6 | dimensions: 256×128 ground · 128(N+M)×128K structure · 256×128 or 256×256 prop |
| 7 | no checkerboard baked into RGB (per-tile correlation on high-passed luminance) |
| 8 | some intermediate alpha exists (a painterly edge, not a thresholded one) |
| 9 | no loader resize: the file is the size Godot draws |

Plates that fail are kept as evidence under `assets/dimetric/_rejected/` (a `.gdignore` folder), never
salvaged. The eight original white plates under `assets/iso/` live there now.

## The library

```
assets/dimetric/
  MANIFEST.json        generated: every plate, its kind, footprint, path, ANDON result
  camera/              dimetric_60_45.py, diamond_clip.py, calibration_square.png
  andon/               iso_andon.py, build_manifest.py
  ground/              dirt_a, dirt_b, stone_a (256×128 diamonds; colour bled past the edge, then clipped)
  structures/<id>/     beauty.png + sidecar.json (slab row, strip width, storeys, azimuth)
  props/<id>/          beauty.png + sidecar.json (foot pixel; light_px for the torch)
```

The runtime reads `MANIFEST.json` and loads only entries whose `andon` is `pass`. Authoring is a separate
concern from rendering: the stage never generates art, and the camera script never touches the stage.

## The lie budget

**Hashed by the engine:** zone id, facing at rest, who is in which zone at tick T.

**Allowed lies:** the destination highlight on the input frame; the walk tween after an admitted zone
change; camera trauma and HUD flash from `felt.uiEffects`; walking inside a zone, which the sim never hears.

**Forbidden:** analog velocity as truth; hashing a tween's `t`; interpolating occupancy; a physics body
that collides on its own; juice that writes hashed state. There is no `CharacterBody2D` in this client and
there will not be one.
