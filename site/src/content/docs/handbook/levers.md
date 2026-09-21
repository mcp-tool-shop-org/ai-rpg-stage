---
title: Authoring levers
description: What this client will redraw when you change a world, and what it will refuse to decide.
sidebar:
  order: 4
---

This client does not author a world. It draws one. The levers below are the ones it actually reads. Everything else — a new room, a gate, who the simulation says is present — is turned in [World Forge](https://mcp-tool-shop-org.github.io/world-forge/handbook/levers/) and enforced by the engine.

## What a drawing change looks like

| Lever | Where it lives | What you see |
|---|---|---|
| Floor plate | `fixtures/pack.json` → `presentation.floor` | Atlas slot on that zone's 3×3. `stone_wet` is the wet quay. `stone_a`, `dirt_a`, and `dirt_b` are the other slots. An unknown plate id is skipped. If `floor` is absent, the long quay is still wet. |
| Who stands where | `presentation.occupancy` | A Foundry sprite on that cell, facing one of eight buckets. The character field is a pack id (`merchant`, `elder`, `scribe`, `guard`, `child`, `fisherman`), not a display name. |
| Zone anchor | `presentation.zoneCells` | Where that zone's diamond sits. Buildings and the click target use it. |
| Fallback cast | `fixtures/harbour-occupancy.json` | Used only when the pack has no occupancy rows. |
| Heard cue | `assets/felt/<cueId>.wav` | The mixer plays the file. A missing file is a sine tone of the same cue id. Overlay stings do not replace the zone stem. |
| A new plate | `assets/dimetric/`, listed in `MANIFEST.json` with `andon: pass` | The runtime loads passing plates only. A plate that fails the ANDON stays out. |

Occupancy in the simulation is still a **zone id**. A cell is how the sprite is drawn inside that zone. The stage never writes the cell back.

## Regenerate, then play

From a World Forge checkout, one command writes the scene and the pack the stage commits, and the engine pack the sidecar loads:

```bash
npx tsx dogfood/export-stage-fixture.ts \
  --world=salt-road \
  --out=<this-repo>/fixtures \
  --doctor \
  --strict \
  --engine-out=dogfood/output/salt-road/pack.json
```

The scene is a join graph. It does not reference `player.gd` or `world_data`. Gate text is metadata on the zone node; this client displays it and does not decide the gate.

`node tools/play.mjs` from this repo starts the sidecar on TCP and opens the harbour.

## Plates come after the lever

The library under `assets/dimetric/` is the set of plates a lever can name. Adding a plate does not add a room. A room is a zone in World Forge. Paint a plate when a lever you already have (`stone_wet`, a structure, a prop) has no passing art, and run the ANDON before it is allowed into `MANIFEST.json`. See [The dimetric camera](./dimetric/).
