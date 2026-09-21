---
title: Reference
description: Keys, launcher flags, headless flags, suites, directories, manifest and sidecar fields, environment.
sidebar:
  order: 5
---

## Keys

| Key | Does |
|---|---|
| click a diamond | walk there; a diamond in a neighbour zone submits `move` |
| `1`–`9` | walk through the numbered door |
| `Space` | wait a round |
| `I` | show the prose log |
| `J` | camera juice on / off |
| `M` | mute |
| `Esc` | leave |

## `tools/play.mjs`

| Flag | Default |
|---|---|
| `--seed <n>` | `71` |
| `--port <n>` | `47820` |
| `--shock <district:metric:delta@round>` | `dockward:stability:-25@2` |
| `--no-shock` | off |
| `--engine <dir>` | `../ai-rpg-engine` |
| `--forge <dir>` | `../world-forge` |
| `--headless` | off (start the sim only and print the port) |

Exit 1 on a failed precondition, with the command that fixes it printed. Exit 0 when the window closes.

## Godot command lines

| Command | What |
|---|---|
| `godot --headless --path . --import` | Populate `.godot/` (imports, class cache). Run once after checkout |
| `godot --headless --path . --script res://tools/headless.gd` | The suite |
| `… headless.gd -- --only=<suite>` | One suite. **One** name; a comma list matches nothing and fails |
| `godot --path . -- --attach=<host:port>` | Open the stage against a sidecar you started |
| `godot --path . --script res://tools/screenshot.gd --resolution 1600x900 -- --out=<png>` | Capture the standing set, or a live session with `--attach` |
| `… screenshot.gd -- --zone=<id> --tags=a,b` | Capture a zone in a given dressing state |

## Suites

`tests/test_<name>.gd`, discovered by glob. CI asserts that every one of these ran.

| Suite | Proves |
|---|---|
| `diorama` | the stage stands up; a re-dress swaps dressing and moves nothing; cast carries normal maps; eight facings bucket correctly; prose reaches the stage; the stage has no way to adjudicate a gate |
| `felt_juice` | `uiEffects` become killable camera offsets that never move a hashed node |
| `felt_mixer` | cue ids route to buses; overlay stings do not kill the zone stem |
| `felt_voice` | the spoken line is spoken once, dialogue only |
| `framing` | camera framing math |
| `iso_math` | 2:1 conversion is invertible and cell-stable; Cartesian east is a screen diagonal |
| `iso_world` | the play view is an isometric `TileMapLayer`, Y-sorted, with a Foundry player on a blob and the iso camera current |
| `live_session` | the sim drives the stage over a real sidecar; staleness is reported, never corrected |
| `scene_join` | zone ids reconcile with scene nodes both ways; the doctored fixture fails both ways, naming the ids |
| `tick_queue` | ticks apply in order; gaps are detected |
| `wire_session` | the JSON-RPC session end to end |

`verify.sh` = import + all suites + ANDON re-gate of every `MANIFEST.json` entry + site build.

## Directories

| Path | Holds |
|---|---|
| `client/` | `network_client.gd`, `event_bus.gd`, `tick_queue.gd`, `scene_join.gd`, `framing.gd`, `foundry_pack.gd` |
| `stage/` | `diorama.gd/.tscn`, `session.gd`, `playable.gd` (HUD + input), `light_rig.gd`, `dressing.gd`, `felt_*.gd`, `sprite_binder.gd` |
| `stage/iso/` | `iso_math.gd`, `iso_world.gd`, `iso_structure.gd`, `iso_actor.gd`, `iso_prop.gd` |
| `assets/dimetric/` | the town kit (see [The dimetric camera](../dimetric/)) |
| `assets/characters/<id>/` | Foundry HD packs: `albedo/`, `normal/`, `mask/`, `depth/`, 8 facings each, `pack.json` |
| `fixtures/` | `world.tscn`, `world.doctored.tscn`, `salt-road.manifest.json`, `pack.json` |
| `tools/` | `headless.gd`, `test_case.gd`, `screenshot.gd`, `sidecar_harness.gd`, `play.mjs`, `iso_andon.py` (shim to the library's ANDON) |
| `docs/` | brand source, the C4 diorama report, screenshots |

## `MANIFEST.json` entry

```json
{
  "id": "shed_2x2",
  "kind": "structure",
  "path": "structures/shed_2x2/beauty.png",
  "footprint": [2, 2],
  "andon": "pass",
  "phase": 1,
  "andon_log": "structures/shed_2x2/beauty.andon.json",
  "resolution": [512, 768],
  "sidecar": "structures/shed_2x2/sidecar.json"
}
```

Top level: `tile` `[256, 128]`, `strip_px` `128`, `person_to_storey` `0.33`, `camera` (Euler, sensor fit,
`px_per_bu`), `sun_euler_deg`, `andon.version`, `renderer.blender`. The runtime loads only entries with
`"andon": "pass"`.

## Structure sidecar

| Field | Meaning |
|---|---|
| `footprint` | `[N, M]` tiles |
| `resolution` | `[width, height]` px |
| `slab_width_px` | width of the near diamond, `128·(N+M)` |
| `slab_row_px` | image row of the near vertex (the foot) |
| `strip_px` | `128` |
| `storeys` | count; facade is `384·storeys` px |
| `azimuth_deg` | light azimuth, `135` |
| `sun_euler_deg`, `camera_euler_deg` | the lamp and camera this plate was rendered with |

A prop sidecar carries `foot_px` (`[w/2, h-1]`, the cell's near vertex) and, for a torch, `light_px`, the
flame's pixel position for the client's `PointLight2D`.

## Environment

| Variable | Effect |
|---|---|
| `AI_RPG_ENGINE_DIR` | Engine checkout for the harness and the live suites; default is the sibling `../ai-rpg-engine` |
| `AI_RPG_TTS_URL` | Optional speech endpoint for `felt_voice`; without it the line is shown, not spoken |

## Support

`0.x`, no tagged release; `main` is the supported line. Godot 4.7.x on Windows, macOS, and Linux, run from
source. Security policy and reporting contact: `SECURITY.md`. License: MIT.
