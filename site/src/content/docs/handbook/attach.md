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
(`SIDECAR_MANIFEST_REQUIRED`). The launcher passes `fixtures/salt-road.manifest.json`.

## The handshake

`NetworkClient.attach(host, port)` sends `initialize` with the client's name and version and asks for
three additive capabilities:

| Capability | What the stage gets | What the stage does with it |
|---|---|---|
| `notifications` | Server-pushed `sim/tick` events | Applies them in order through the tick queue |
| `hashes` | A state hash per tick | Records it; compares on every snapshot; reports drift |
| `audio` | The `felt` payload on submit, advance, and matching ticks | Plays cues; shakes the camera; speaks the line |

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

## Ticks and staleness

The stage keeps the tick number it believes the sim is at and the hash it recorded for it. A snapshot is
authoritative about both. When they disagree the client marks itself **stale** and the session logs one of:

```
[stale] tick drift: sim is at 14, stage believes 12
[stale] no recorded hash for tick 14 — the stage never saw it
[stale] state drift at tick 14: sim reports 9f3c…, stage recorded 7a10…
[stale] could not snapshot: <message>
```

Reported, never corrected. A stage that "fixed" a mismatch would be a second source of truth. What happens
next is a fresh snapshot and a redraw from it; the sim is never patched, and nothing the stage drew is sent
back.

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
| `bad --attach target: …` | Not `host:port` | `--attach=127.0.0.1:47820` |
| `could not attach to …` | Nothing listening, or wrong port | `node tools/play.mjs --headless` prints the port it opened |
| launcher: `✗ engine CLI not built` | `packages/cli/dist/bin.js` missing | `cd ../ai-rpg-engine && npm ci && npm run build` |
| launcher: `✗ this engine ref has no --listen transport` | Old engine checkout | Update the engine to a ref that ships the TCP sidecar |
| `[stale] …` in the log | Client and sim disagree | Nothing to fix in the stage: it re-snapshots. If it repeats every tick, the engine build and the stage's expectations have drifted; check both versions |

## Security posture

No credentials cross the wire. Nothing is downloaded or executed at runtime. The stage writes only to
Godot's user directory. Whoever controls the endpoint controls what is rendered, so point the stage only at
an engine you trust, on a network you trust. Full policy: `SECURITY.md` in the repository.
