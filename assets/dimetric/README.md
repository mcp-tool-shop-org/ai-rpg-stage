# Dimetric Town Asset Library (v0.1.0)

Spec (the contract): `E:\AI\readouts\dimetric-knowledge\specs\dimetric-asset-library.md`.
Receipt for this build: `RECEIPT.md`. Inventory with per-file ANDON results: `MANIFEST.json`.

**What this is.** Reusable 2:1 dimetric art for a Godot 4.7 `TileMapLayer` town: clipped ground diamonds
(256×128), sliced structures delivered as whole RGBA plates with a sidecar the slicer can trust, and an
ANDON that refuses any plate before it enters `res://`. The projection is a Blender camera setting
(rotation X 60°, Z 45°, orthographic, `ortho_scale = √2·N`), not a prompt.

**Rules that never bend**
- Every PNG passes `andon/iso_andon.py` first (exit 0). Anything else goes to `_rejected/` with its log.
- Alpha comes from Blender's Film Transparent. Nothing is keyed, matted, cropped or resized here.
- One Sun, one azimuth (`sun_euler_deg` in `MANIFEST.json`), for every plate.
- Ground colour bleeds past the diamond before `camera/diamond_clip.py` applies the alpha; in Godot set
  `use_texture_padding = true` on the atlas source.
- No baked contact shadow on structures or props: the client draws the blob.
- Person = 128 px; one-storey facade = 384 px (1 : 3). One constant for the whole map.

**Layout**
```
camera/     dimetric_60_45.py (headless bpy), diamond_clip.py, calibration_square.png + calibration_andon.json
andon/      iso_andon.py (gates 0–9, exit 1 on any FAIL) — the ANDON MANIFEST.json points at
ground/     dirt_a, dirt_b, stone_a (.png + .json ANDON log); _raw/ keeps pre-clip renders (.gdignore)
structures/ shed_2x2/ beauty.png, sidecar.json, blockout.blend, beauty.andon.json
props/      (phase 2; crate_1x1/ was written by a different generator, tools/iso_make_proof_kit.py — see RECEIPT)
_rejected/  the eight retired assets/iso plates + their logs (.gdignore: Godot never imports them)
```

**Render a new plate**
```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --factory-startup ^
  --python camera\dimetric_60_45.py -- --scene ground --variant a --n 1 --name dirt_c_raw --out ground\_raw
python camera\diamond_clip.py ground\_raw\dirt_c_raw.png ground\dirt_c.png
python andon\iso_andon.py ground\dirt_c.png --kind ground --json ground\dirt_c.json
```
Structures: `--scene house --n 3 --m 3 --storeys 2 --roof gable` (or `--scene shed`, `--scene stair`),
`--out structures\<id> --name beauty --save blockout.blend`, then `iso_andon.py --kind structure --footprint N,M`.
Props: `--scene prop --prop barrel|crate|torch|bollard|well|cart --out props\<id> --name beauty`, then
`iso_andon.py --kind prop` (add `--slab` only if the prop stands on a diamond slab). A torch's render.json
carries `light_px`, the flame's pixel position for the client's `PointLight2D`.

**Godot import (defaults already match)**: Compress Lossless, Fix Alpha Border on, Premult Alpha off, VRAM
compressed off, mipmaps off for ground; mipmaps on for tall strips only if the camera zooms out.

**Screen mapping this rig produces** (from the calibration render): world +X → screen down-right (the
stage's cart x), world +Y → screen up-right; a footprint's near (bottom) vertex is world (N, 0, 0), left is
(0, 0), right is (N, M), top is (0, M). `TileMapLayer` DIAMOND_DOWN matches.
