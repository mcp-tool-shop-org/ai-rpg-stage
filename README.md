<p align="center">
  <strong>AI RPG Stage</strong><br>
  <em>A Godot 4 client for a simulation it does not own.</em>
</p>

---

`ai-rpg-stage` renders a world that something else decides. It attaches to a
running [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) over
JSON-RPC, submits what the player is trying to do, and draws what comes back. It
holds no rules. It advances no clock. When it disagrees with the simulation, the
simulation is right and the stage says so out loud.

That constraint is the product. A deterministic simulation whose client is allowed
to guess is a simulation with two truths, and the second one desynchronises
quietly. Everything here is arranged so the stage cannot become the second truth.

## What lives here

| | |
|---|---|
| `client/` | The parts that talk to the engine and bind its vocabulary to the scene tree |
| `stage/` | The rendered world — scene, lighting rig, dressing |
| `fixtures/` | A generated world + its wire-side truth, committed as a pair so the join between them can be checked |
| `tools/` | The headless runner |
| `tests/` | Proofs, each with a control that makes it fail |

## Running the suite

Requires Godot **4.7.x** on `PATH`.

```bash
godot --headless --path . --import && godot --headless --path . --script res://tools/headless.gd
```

The runner prints `PASS:` / `FAIL:` lines and a `verdict=` line, and exits
non-zero on any failure. It also fails on a test that asserted nothing and on a
`--only=` filter that matched nothing — an empty run is a failure here, not a
pass.

One suite, one file:

```bash
godot --headless --path . --script res://tools/headless.gd -- --only=scene_join
```

## The join, and why it has a doctored fixture

The simulation speaks in zone ids. The stage is a tree of nodes. `client/scene_join.gd`
turns one into the other, and `fixtures/` carries two scenes: the real export, and
one with a single zone id altered. The test reconciles both. The real one must
match in both directions; the altered one must fail in both directions, naming the
real id as missing from the scene and the altered id as absent from the wire.

Without the second fixture the first proves only that two lists happened to agree
on the day they were generated.

The exported scene also carries `metadata/entry_gate*` on gated zones. The stage
never reads it to decide anything. Gates are engine rules: the stage submits the
move and renders the refusal it gets back, including the reason a person gave for
it. `client/scene_join.gd` offers no way to evaluate a gate, on purpose.

## Regenerating the fixtures

The fixtures are produced by World Forge and committed here, so this repo needs no
JavaScript toolchain to run or to build. From a `world-forge` checkout:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<path-to-this-repo>/fixtures --doctor
```

The generator refuses to write a fixture with zero zones, duplicate zone ids, a
gate count that disagrees with the authored world, or a zone the scene carries no
node for. A generated hole is worse than a missing file, because a hole passes.

## License

MIT © mcp-tool-shop
