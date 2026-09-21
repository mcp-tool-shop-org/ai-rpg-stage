<p align="center">
  <a href="README.md">English</a> | <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/ai-rpg-stage/readme.png" width="400" alt="AI RPG Stage">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/ai-rpg-stage/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/ai-rpg-stage/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://mcp-tool-shop-org.github.io/ai-rpg-stage/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
  <a href="https://mcp-tool-shop-org.github.io/ai-rpg-stage/handbook/"><img src="https://img.shields.io/badge/Handbook-read-orange" alt="Handbook"></a>
</p>

<p align="center"><em>A Godot 4 client for a simulation it does not own.</em></p>

---

`ai-rpg-stage` renders a world that something else decides. It attaches to a
running [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) over
JSON-RPC, submits what the player is trying to do, and draws what comes back. It
holds no rules. It advances no clock. When it disagrees with the simulation, the
simulation is right and the stage says so out loud.

That constraint is the product. A deterministic simulation whose client is allowed
to guess is a simulation with two truths, and the second one desynchronises
quietly. Everything here is arranged so the stage cannot become the second truth.

**Status:** `0.x`, no tagged release yet; `main` is the supported line. Godot **4.7**.

## What it draws

The play camera is **2:1 dimetric**: one continuous harbour on a Godot
`TileMapLayer` (isometric, diamond-down, 256×128 cells), Y-sorted, with
[Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) HD
characters (8 directions, albedo + normal, foot pivot) standing on contact blobs.
Buildings are plates that pass a projection gate and are sliced into 128 px
strips, so Y-sort has one drawable per diamond. Torches are `PointLight2D`s that
light the characters' normal maps. The HUD is a plaque, not a panel that eats the
dirt.

Occupancy in the engine is still a **zone id**. A diamond under the cursor is a
view of a zone, never a second spatial simulation. The contract both sides keep is
[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
in the engine handbook.

Town art lives under [`assets/dimetric/`](assets/dimetric/README.md). Every plate
was rendered through a Blender orthographic camera at X 60° / Z 45° and must pass
`assets/dimetric/andon/iso_andon.py` before the stage loads it. The gate refuses
the wrong projection, missing alpha, baked backdrops, and anything not on the tile
grid. Nothing under `assets/iso/` is loaded; that folder is dead.

## What lives here

| | |
|---|---|
| `client/` | The parts that talk to the engine and bind its vocabulary to the scene tree: network client, event bus, tick queue, scene join, Foundry pack loader |
| `stage/` | The rendered world: the dimetric harbour (`stage/iso/`), the light rig, the felt mixer and voice, the plaque HUD, the session that drives them |
| `assets/dimetric/` | The town kit: ANDON, camera script, ground tiles, structures, props, `MANIFEST.json` |
| `assets/characters/` | Vendored Foundry HD packs (townsfolk) |
| `fixtures/` | A generated world and its wire-side truth, committed as a pair so the join between them can be checked |
| `tools/` | The headless test runner, the screenshot tool, the play launcher, the sidecar harness |
| `tests/` | Eleven proof suites, each with a control that makes it fail |

## Running it

Requires Godot **4.7.x** on `PATH` as `godot`. The engine is a sibling checkout
(`../ai-rpg-engine`, or `AI_RPG_ENGINE_DIR`), built with `npm run build`.

**Play Salt Road** (starts the sidecar with the harbour loaded, waits for the
port, opens the stage, shuts the sim down when the window closes):

```bash
node tools/play.mjs
```

Options: `--seed <n>` (default 71), `--port <n>` (default 47820),
`--shock <district:metric:delta@round>` or `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--headless` (start the sim only and print the port).

| Key | Does |
|---|---|
| click a diamond | walk there; a diamond in a neighbour zone submits `move` |
| `1`–`9` | walk through that door |
| `Space` | wait a round |
| `I` | show the prose log |
| `J` | camera juice on/off |
| `M` | mute |
| `Esc` | leave |

**Run the suite** (headless, no window; the suites that need a live sim skip
with a named reason when no engine is present):

```bash
./verify.sh
```

`verify.sh` imports the project, runs every `tests/test_*.gd`, re-gates every
runtime plate in `MANIFEST.json`, and builds the site when `site/` exists. The
same thing by hand:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

The runner prints `PASS:` / `FAIL:` lines and a `verdict=` line and exits
non-zero on any failure, on a test that asserted nothing, and on a `--only=`
filter that matched nothing. A filter is **one** suite name; a comma list matches
nothing, and an empty run is a failure here, not a pass.

## Attaching

The stage connects **outbound** over TCP to a sidecar the operator names
(`--attach=host:port` on Godot's command line; `play.mjs` passes it). The
handshake asks for `capabilities.hashes` (per-tick staleness) and
`capabilities.audio` (the `felt` payload: zone stems, overlay stings, the spoken
line, camera trauma). On a hash mismatch the stage reports it on the status line
and in the log, stops trusting itself, and re-snapshots. It never patches the sim.

A sidecar booted with `--content` still needs `--manifest`; the launcher passes
`fixtures/salt-road.manifest.json`.

## The join, and why it has a doctored fixture

The simulation speaks in zone ids. The stage is a tree of nodes.
`client/scene_join.gd` turns one into the other, and `fixtures/` carries two
scenes: the real export, and one with a single zone id altered. The test
reconciles both. The real one must match in both directions; the altered one must
fail in both directions, naming the real id as missing from the scene and the
altered id as absent from the wire. Without the second fixture the first proves
only that two lists happened to agree on the day they were generated.

The exported scene also carries `metadata/entry_gate*` on gated zones. The stage
never reads it to decide anything. Gates are engine rules: the stage submits the
move and renders the refusal it gets back, including the reason a person gave for
it. `client/scene_join.gd` offers no way to evaluate a gate, on purpose.

Fixtures are produced by [World Forge](https://github.com/mcp-tool-shop-org/world-forge)
and committed here, so this repo needs no JavaScript toolchain to run or to
build:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

The generator refuses to write a fixture with zero zones, duplicate zone ids, a
gate count that disagrees with the authored world, or a zone the scene carries no
node for.

## Trust and threat model

**Data touched.** The stage reads the scene, fixtures, and plates in this
repository, and the JSON-RPC messages from the one engine endpoint it was pointed
at. It writes only to Godot's own user data directory (editor cache, logs).

**Data not touched.** No files outside the project and Godot's user directory.
No credentials are read, stored, or sent; the wire protocol is unauthenticated by
design and assumes a trusted local endpoint. **No telemetry** is collected or
sent, by the stage or by anything it bundles. No code is downloaded or executed
at runtime.

**Permissions.** One outbound TCP connection to the host and port the operator
passes. There is no default endpoint, no discovery, and no listener: nothing here
accepts a connection. Whoever controls the endpoint controls what is rendered, so
point the stage only at an engine you trust, on a network you trust.

**Errors.** Transport faults, refused connections, and staleness are reported as
plain sentences on the status line and in the log (`[stale] state drift at tick
N: sim reports X, stage recorded Y`), never as raw exceptions in the UI. Godot's
own `--verbose` flag turns on engine-level logging; nothing the stage logs
contains a secret because it never holds one.

Full policy and reporting contact: [SECURITY.md](SECURITY.md).

## License

MIT © mcp-tool-shop. See [LICENSE](LICENSE) and [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
