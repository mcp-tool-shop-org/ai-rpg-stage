---
title: Attaching
description: The TCP sidecar, the handshake capabilities, the felt payload, and what a hash mismatch does.
sidebar:
  order: 2
---

## One outbound socket

The stage connects **out** to a sidecar the operator names. There is no default endpoint, no discovery,
and no listener. On Godot's command line:

```bash
godot --path . -- --attach=127.0.0.1:47820
```

`play.mjs` passes exactly that after it has started the sidecar and seen the port accept a connection.
Godot must attach over **TCP**: upstream stdio pipes are unreliable in the engine (godot#102340), so the
sidecar is started with `--listen`.

A sidecar booted with `--content` still needs `--manifest`; without it the engine refuses to load
(`SIDECAR_MANIFEST_REQUIRED`). The launcher passes `fixtures/salt-road.manifest.json`. It also passes
`--unresolved-ai-profile fail` in debug builds, `play.mjs`, and CI (so unresolved profiles abort boot), and
`--unresolved-ai-profile warn` in release exports (surfacing every stderr warning line both in the log and on
screen in the transcript's fallback style).

## The handshake

`NetworkClient.attach(host, port)` sends `initialize` with the client's name and version and asks for
four additive capabilities:

| Capability | What the stage gets | What the stage does with it |
|---|---|---|
| `notifications` | Server-pushed `sim/tick` events | Applies them in order through the tick queue |
| `hashes` | A JS state hash per tick | Records it for snapshot position checks |
| `canonicalHashes` | Canonical state hash per tick (`digest_spec_version` 2) | Recomputes over the patched mirror after every play submit; verifies and resyncs on drift |
| `audio` | The `felt` payload on submit, advance, and matching ticks | Plays cues; shakes the camera; speaks the line |

If `digest_spec_version` is missing or unsupported (`!= 2`), `attach` fails immediately with a visible load error.
The server's `initialize` result is kept as the handshake; `capabilities()` returns what was actually
granted, and the status line shows the engine version.

## What `felt` carries

When `audio` is granted, responses carry a `felt` object that the engine **never hashes**:

- `AudioCommand[]` cue ids: a zone stem, ambient beds, and overlay stings that do not replace the stem.
  `stage/felt_mixer.gd` routes them onto Music / Ambient / Sfx / Voice buses.
- `speaker` — the spoken line, once. `stage/felt_voice.gd` speaks dialogue only; `AI_RPG_TTS_URL` is optional.
- `uiEffects` — camera trauma and HUD flashes. `stage/felt_juice.gd` applies them as killable offsets that
  never move a hashed node. `J` toggles them.

`felt` is omitted entirely when `audio` was not requested, so exact-match clients stay byte-stable.

## Ticks, mirror verification, and bounded resync

Until the baseline `snapshot` lands after `initialize`, the HUD shows a `syncing` state and refuses
play input (`submitAction`, `advance`, door keys, and isometric movement clicks) so no unverified
action runs against an empty mirror. Once the baseline snapshot is applied, the stage maintains its
mirror from every incremental delta using the shared spec-v2 integer-scaled pre-image format. After
every play submit (`submitAction` and `advance`), the stage recomputes the canonical digest on its
mirror and compares it with the engine's `canonicalHash` for that tick.

When they disagree, the stage marks itself **stale**, requests a full snapshot, computes the first differing
UTF-8 byte offset between pre-images, replaces its mirror from the snapshot, and immediately recomputes and
verifies the snapshot's canonical digest:

```
[stale] state drift at tick 14: expected 9f3c…, mirror 7a10…, first differing pre-image offset 42 (resync 1/3)
[halt] resync cap exceeded (4 consecutive mismatches, max 3): …
```

Resyncing from the engine's own snapshot is not the stage inventing a world — the simulation stays right and
is never patched. Consecutive resyncs are capped at **3**: if a 4th mismatch occurs in a row (or a fresh
snapshot itself fails verification), play stops with a visible error on screen and in the log.

## What is submitted

Exactly one kind of intent leaves the stage: an action. `move` takes an **adjacent zone id**. The engine
checks adjacency from the actor's own zone and replies with `action.rejected` (with a reason, including the
line a person gave for a gate) or the events of the move. The stage renders whichever it gets.

Clicking a diamond inside the current zone walks the sprite there at a fixed speed and submits nothing.
Clicking a diamond in a neighbour zone walks to the boundary and submits `move`. On a reject the actor
faces the door and stays; it never left, so there is nothing to walk back.

## Troubleshooting

| Status line | Cause | Fix |
|---|---|---|
| `not attached — run: node tools/play.mjs` | Godot was started without `--attach` | Use the launcher, or pass `--attach=host:port` |
| `syncing — …` | Handshake done; waiting for baseline `snapshot` | Wait for the initial snapshot; play input unlocks automatically once synced |
| `bad --attach target: …` | Not `host:port` | `--attach=127.0.0.1:47820` |
| `could not attach to …` | Nothing listening, or wrong port | `node tools/play.mjs --headless` prints the port it opened |
| launcher: `✗ engine CLI not built` | `packages/cli/dist/bin.js` missing | `cd ../ai-rpg-engine && npm ci && npm run build` |
| launcher: `✗ this engine ref has no --listen transport` | Old engine checkout | Update the engine to a ref that ships the TCP sidecar |
| `[stale] …` in the log | Client mirror diverged | The stage logged the pre-image offset and resynced from a full snapshot. More than 3 consecutive mismatches halt play |
| `load error — unsupported digest_spec_version …` | Engine/stage digest spec mismatch | Point the stage at an engine speaking `digest_spec_version` 2 |

## Fallback event rendering

Events in `Session.RENDERED` (`world.zone.entered`, `world.zone.state.changed`, `world.zone.gate.refused`,
`action.rejected`, `encounter.spawned`) drive bespoke scene and prose handlers. Any other simulation event
renders one transcript line in a distinct muted `[fallback]` style naming the event `type` and its sorted
`payload` keys (an internal research report, 2026-11-24).

## Security posture

No credentials cross the wire. Nothing is downloaded or executed at runtime. The stage writes only to
Godot's user directory. Whoever controls the endpoint controls what is rendered, so point the stage only at
an engine you trust, on a network you trust. Full policy: `SECURITY.md` in the repository.
