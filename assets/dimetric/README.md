# Dimetric Town Asset Library (v0.1.0)

**Split of labour (settled 2026-09-20).** This folder authors plates. The Godot runtime consumes them. Do not generate PNGs from `tools/iso_make_proof_kit.py` (retired). Do not add a second ANDON.

| Role | Path |
|---|---|
| Canonical ANDON | `andon/iso_andon.py` (MANIFEST points here) |
| Repo-root shim | `tools/iso_andon.py` → the file above |
| Camera | `camera/dimetric_60_45.py` |
| Inventory | `MANIFEST.json` |
| Receipt | `RECEIPT.md` (local build log) |

**Rules.** Every PNG passes the ANDON (exit 0) before it is a runtime asset. Alpha comes from Film Transparent. One Sun (`sun_euler_deg` in MANIFEST). Ground colour bleeds past the diamond, then `camera/diamond_clip.py`. No baked contact shadows. Person 128 px : one-storey facade 384 px.

**Phase 1 (shipped).** `ground/dirt_a`, `dirt_b`, `stone_a`; `structures/shed_2x2/beauty.png` (512×768 grey-box, ANDON pass). Calibration: `camera/calibration_square.png` at 26.57°.

**Phase 2 (shipped 2026-09-20, wired in PR #6, released v0.2.0).** `ground/stone_wet`; `structures/counting_house` (3×3), `warehouse` (3×3), `stair` (2×3); `props/well_1x1`, `cart_1x1`, `barrel_1x1`, `crate_1x1`, `torch_1x1`, `bollard_1x1`. All grey-box, all ANDON-green, all in `MANIFEST.json` v0.2.0 (23 entries, 14 pass). Sources under `_src/<id>/blockout.blend`. **Phase 3** (painterly repaint under the blockout's depth+normal ControlNet) waits on an explicit spend go.

**Godot import.** Lossless, Fix Alpha Border on, Premult off, no VRAM compression. Keep `.blend` sources out of the same folder as runtime PNGs (they live under `_src/`) so the importer is not blocked by a missing Blender path.
