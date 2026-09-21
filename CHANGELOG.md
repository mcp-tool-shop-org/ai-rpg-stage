# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

- **The committed fixture is the 4.9.0 join-graph export.** `world.tscn` no longer
  needs `player.gd` or `world_data`, and `pack.json` is that same export
  (presentation included). CI regenerates both from `FORGE_REF`.
- **`presentation.floor` paints the atlas.** `long-quay: stone_wet` comes from
  the pack. If the key is absent, the long quay is still the wet slot.
- ANDON reconfigures stdout to UTF-8 so a passing gate can print its delta
  on Windows cp1252.
- CI cancels the same-repo push + pull_request double run. Path filters stay.

## [0.2.0] - 2026-09-21

**The felt harbour is playable.** The stage walks one continuous 2:1 dimetric
town, the named cast stands on cells an author chose rather than cells the
client guessed, the quay is wet under the light, and the sim can plant an
encounter on a diamond. It still decides nothing: every cell, facing and floor
here is drawing truth, and the simulation wins any dispute about which zone a
person is in. This is the first release; history before it lives in the git log.
273 checks across eleven headless suites.

### Added

- **Full treatment (public surfaces).** Brand logo in the README, trust and threat-model section,
  keys and launcher flags, `verify.sh` (import + suite + plate re-gate + site build), landing page and
  Starlight handbook under `site/` (deployed by `pages.yml`), GitHub metadata, translations.
  `project.godot` carries `config/version="0.2.0"`.
- CI's "every expected suite ran" manifest lists all eleven suites (it had drifted to six).
- **Felt harbour runtime.** Mixer loads `res://assets/felt/<cueId>.wav` when present
  (sine stand-in otherwise). Named cast stands on occupancy cells
  (`fixtures/harbour-occupancy.json`); `FrontProof`/`BehindProof` are not the
  play layout. `encounter.spawned` plants IsoActors on zone diamonds. Long-quay
  diamonds use `stone_wet` when that plate is in the library. Juice shakes the
  iso camera.
- **World Forge presentation on the fixture.** `fixtures/pack.json` carries the
  additive `presentation` block (six occupancy rows, zone anchors, `stone_wet`
  on the quay) and `packFormat` `1.1.0`. The harbour prefers pack occupancy and
  `zoneCells` when present, and falls back to the sidecar. CI `ENGINE_REF` is
  engine 3.12.0 (`97d6ef1`). `FORGE_REF` stays on the last scene this repo can
  instantiate (4.9.0's generated `.tscn` references `player.gd` / `world_data`
  this tree does not contain).

### Added (earlier on `main`)

- `SECURITY.md` stating the trust boundary: the stage renders what the engine
  returns and does not validate it, so the endpoint is the security perimeter.
- **Felt mixer.** Cue-id contract on `capabilities.audio`: zone stem + ambient
  beds + overlay stings that do not kill the stem, procedural tones on Music /
  Ambient / Sfx / Voice buses. `J` toggles juice, `M` mutes.
- **Lie budget.** Camera offset shake/flash from `felt.uiEffects`; killable;
  never moves a hashed node.
- **Dialogue-only voice.** Speaks `felt.speaker.text`. Optional `AI_RPG_TTS_URL`.
- **Dimetric harbour (the play camera).** `stage/iso/`: 2:1 math, Godot 4
  `TileMapLayer` isometric 256×128, Y-sort, Foundry HD actors with contact
  blobs (`show_behind_parent`), buildings as 128 px `IsoStructure` strips.
  Ground tiles are ANDON-passing 256×128 diamonds in `assets/dimetric/`.
  The eight white-plate files under `assets/iso/` are not loaded.
- **Plaque HUD.** Zone name and doors top-left; last event as a bottom toast;
  the prose log is behind `I`. Click a diamond to walk; neighbour-zone clicks
  submit `move`. Intra-zone walking is presentation and is not hashed.
- **Library authorship.** Plates are authored under `assets/dimetric/` (ANDON
  `andon/iso_andon.py`). `tools/iso_andon.py` is a shim. The PIL proof-kit
  generator is retired so it cannot overwrite a Blender plate.
- **Harbour set (library v0.2.0).** Counting house, warehouse, stair, well,
  cart, barrel, crate, torch, bollard — ANDON-passing plates, sliced on the
  diamond. Flat leftover `shed_2x2.png` / `crate_1x1.png` copies removed.
