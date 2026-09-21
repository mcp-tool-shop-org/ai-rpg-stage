---
title: Getting started
description: Godot 4.7 on PATH, the engine as a sibling, the play launcher, the headless suite.
sidebar:
  order: 1
---

## What you need

| Thing | Version | Why |
|---|---|---|
| Godot | **4.7.x**, on `PATH` as `godot` | The project pins `4.7` in `project.godot`; CI refuses any other minor |
| Node | 20+ | Only for `tools/play.mjs` (a process launcher) and for building the engine |
| AI RPG Engine | a sibling checkout at `../ai-rpg-engine`, or `AI_RPG_ENGINE_DIR` | The simulation the stage attaches to |
| World Forge | a sibling at `../world-forge` (optional) | Only to regenerate fixtures; the committed ones already work |
| Python 3 + numpy + Pillow | any recent | Only for `verify.sh`'s plate re-gate and for authoring plates |

Build the engine once:

```bash
cd ../ai-rpg-engine && npm ci && npm run build
```

The stage needs `packages/cli/dist/bin.js` to exist there and its `sidecar --listen` transport to be present.
`play.mjs` checks both and prints the fixing command if either is missing.

## Play Salt Road

```bash
node tools/play.mjs
```

The launcher starts the sidecar with the Salt Road pack and manifest, waits until the port genuinely accepts
connections, opens the stage pointed at it, and shuts the sim down when the window closes. It is a process
babysitter: the client itself contains no JavaScript.

| Flag | Default | Meaning |
|---|---|---|
| `--seed <n>` | `71` | Session seed. Every proof in the repo uses 71 |
| `--port <n>` | `47820` | Sidecar port |
| `--shock <district:metric:delta@round>` | `dockward:stability:-25@2` | Scenario cue: the quay turns on round 2 |
| `--no-shock` | | Run with no cue |
| `--engine <dir>` | `../ai-rpg-engine` | Engine checkout |
| `--forge <dir>` | `../world-forge` | World Forge checkout |
| `--headless` | | Start the sim only, print the port, wait. For attaching the editor or driving it by hand |

In the window:

| Key | Does |
|---|---|
| click a diamond | walk there inside the current zone; a diamond in a neighbour zone submits `move` |
| `1`–`9` | walk through the numbered door |
| `Space` | wait a round |
| `I` | show the prose log |
| `J` | camera juice on / off |
| `M` | mute |
| `Esc` | leave |

The status line top-left says `attached — <engine version>` when the handshake succeeded, and a plain
sentence when it did not (`could not attach to 127.0.0.1:47820`, `bad --attach target: …`).

## Run the suite

```bash
./verify.sh          # import + every suite + plate re-gate + site build (if site/ exists)
./verify.sh --quick  # skip the site build
```

By hand, which is exactly what CI runs:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
```

The runner discovers `tests/test_*.gd`, runs each suite against a fresh assertion harness, prints `PASS:` /
`FAIL:` lines and a final `verdict=` line, and exits non-zero on:

- any failed check,
- a suite that asserted nothing,
- a `--only=` filter that matched no suite,
- discovering no tests at all.

An empty run is a failure here, not a pass. Run one suite with its **single** name:

```bash
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

`--only=a,b` matches nothing and therefore fails. Suite names are listed in the [Reference](./reference/).

Suites that need a live simulation (`live_session`, `wire_session`) resolve the engine from
`AI_RPG_ENGINE_DIR` or the sibling checkout and skip with a named reason when neither exists. CI checks
that all eleven suites actually ran, so a renamed test file is a red build rather than a silent shrink.

## Take a screenshot

```bash
godot --path . --script res://tools/screenshot.gd --resolution 1600x900 -- --out=shot.png
```

Deliberately **not** headless: a headless capture is a blank image. With `--attach=host:port` it captures a
live session; without one it captures the standing set and says so on screen.

## Regenerate the fixtures

The fixtures under `fixtures/` are exported by World Forge and committed as a pair (the scene and its
wire-side manifest) so the join between them can be checked. From a `world-forge` checkout:

```bash
npx tsx dogfood/export-stage-fixture.ts \
  --world=salt-road \
  --out=<this-repo>/fixtures \
  --doctor \
  --strict \
  --engine-out=dogfood/output/salt-road/pack.json
```

Salt Road is the harbour this client plays. `--strict` refuses a presentation block that draws someone
in the wrong room. The scene is a join graph: zone nodes and gate text, no `player.gd`, no `world_data`.
The `--engine-out` file is what the sidecar loads, and it does not carry `presentation` — that block stays
on `fixtures/pack.json`. The exporter also refuses zero zones, duplicate ids, a gate count that disagrees
with the authored world, or a zone the scene has no node for.
