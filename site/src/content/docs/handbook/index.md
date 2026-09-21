---
title: AI RPG Stage Handbook
description: A Godot 4 client that renders a simulation it does not own.
sidebar:
  order: 0
---

`ai-rpg-stage` is the Godot 4.7 client of [AI RPG Engine](https://github.com/mcp-tool-shop-org/ai-rpg-engine).
It attaches to a running engine sidecar, submits what the player is trying to do, and draws what comes back.
It holds no rules and advances no clock. When it disagrees with the simulation, the simulation is right and
the stage says so.

This handbook is about the **client**. The engine's own handbook covers the simulation; the chapter both
sides keep is [Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/).

## Where truth lives

| Owned by the engine | Owned by the stage |
|---|---|
| Occupancy, as a **zone id** | Where on the diamond a sprite stands inside that zone |
| Whether a `move` is admitted | The walk tween played after it is admitted |
| Every rule, gate, and tick | The highlight under the cursor, the camera shake, the toast |
| The state hash | Reporting a mismatch, then re-snapshotting |

The stage may **lie for the eye**: a sprite tweens, a camera shakes, a toast flashes. None of that is hashed
and none of it is sent back. What the stage may never do is hold a second copy of the truth and reconcile
against it. That is the failure the whole layout is arranged to prevent.

## The two surfaces

**The wire.** `client/` talks JSON-RPC over TCP to the sidecar: a network client with a handshake and a
tick queue, an event bus, and a scene join that maps zone ids onto scene nodes and proves it both ways
against a doctored fixture. See [Attaching](./attach/).

**The picture.** `stage/` draws a **2:1 dimetric harbour**: one `TileMapLayer` of 256×128 diamonds,
Y-sorted, Sprite Foundry HD characters on contact blobs, buildings sliced into 128 px strips, torches that
light normal maps, a plaque HUD. Every plate in `assets/dimetric/` passed a projection ANDON before it was
allowed in. See [The dimetric camera](./dimetric/).

## Pages

- [Getting started](./getting-started/): Godot 4.7, the play launcher, the headless suite, `verify.sh`.
- [Attaching](./attach/): the TCP sidecar, the handshake capabilities, `felt` audio, what a hash mismatch does.
- [The dimetric camera](./dimetric/): projection, Y-sort, strips, blobs, the ANDON, the lie budget.
- [Authoring levers](./levers/): which drawing knobs this client reads, and which decisions stay in World Forge and the engine.
- [Reference](./reference/): keys, flags, suites, directories, manifest and sidecar fields, environment.

## What this is not

- Not a game. It is one rendering surface for a simulation that other hosts (the engine's terminal `run`
  loop, for one) also render.
- Not an editor for the world. Fixtures are exported by World Forge and committed; the stage never edits them.
- Not a physics world. There is no `CharacterBody2D`, no WASD, no collision that the engine cannot see.
