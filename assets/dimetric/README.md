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

**Phase 2** is harbour remakes (counting house, warehouse, stair, well, cart, barrel, torch, bollard). Author them with the camera script; do not salvage `_rejected/`.

**Godot import.** Lossless, Fix Alpha Border on, Premult off, no VRAM compression. Keep `.blend` sources out of the same folder as runtime PNGs (they live under `_src/`) so the importer is not blocked by a missing Blender path.
