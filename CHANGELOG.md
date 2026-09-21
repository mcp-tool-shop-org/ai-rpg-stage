# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

No tagged release yet. `main` carries the JSON-RPC client, the stage renderer,
and the fixture-driven test suite; history before this file lives in the git log.

### Added

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
