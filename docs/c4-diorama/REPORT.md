# C4 — The Reference Diorama: REPORT

**Cycle:** fourth rung of the 2.5D arc ([[ai-rpg-engine-2p5d-quality-bar]] §5, row C4).
**Shape:** BUILD, across three repos. Marathon-framed: no deadline language anywhere in
this cycle's artefacts.
**Director's rulings carried:** client = **Godot** · world = **merchant / Salt Road** ·
content **more human**.

| | |
|---|---|
| NEW `mcp-tool-shop-org/ai-rpg-stage` | `main` scaffold + branch `feat/c4-wire-and-diorama` |
| ai-rpg-engine | branch `feat/c4-socket-attach`, from `021d7b2` |
| world-forge | branch `feat/c4-stage-lane`, from `0065ffb` |
| Suites | stage **0 → 168 checks** (6 suites) · engine **6751 → 6791** · forge **2431 → 2435** |
| Artefacts | `docs/played.png` · `docs/diorama-intact.png` · `docs/diorama-damaged.png` · this report |

---

## 1. The headline

**Three of C4's four clauses are live over a real wire, on a world authored in the Forge,
rendered by a client that decides nothing. The fourth clause is the Director's to close.**

C0 measured a content path that reached only a validator. C1 made a pack boot. C3 made the
arrived content mean something. C4 makes it **visible and played**:

```
movement    the player walks through real `move` intents; the scene's player node
            follows the sim's idea of where they are
a refusal   walking into the bonded warehouse renders Halle's own sentence —
            "It's my name beside whatever leaves here, and I've a mother in Dockward."
spawns      the anchor fires on entry; spawned entities become real nodes carrying
            the sim's own entity ids
a re-dress  a district shock arrives naming its own cause — "district stability fell
            25 from its baseline of 38" — and the quay visibly re-dresses, in that
            district only
```

Three numbers carry the cycle:

- **0.425** — the anchor's observed firing rate over 40 seeds against the authored 0.45.
- **0** — zone-state changes produced by 60 world ticks and 8 rounds of real combat. The
  shock has no in-play producer, and finding that out is worth more than the diorama.
- **168** — checks in a repo that did not exist at the start of the cycle, every suite
  carrying a control that makes it fail.

---

## 2. What each phase closed

| Phase | Built | Proven by |
|---|---|---|
| P0 | the repo, the headless runner, the `.tscn`↔wire join | the join reconciles both directions, and a scene with ONE altered zone id fails in both directions at once |
| P1 | TCP attach on the engine; framing, client, bus, tick queue in Godot | one session byte-identical in-process, over stdio, AND over TCP; strict-in re-proven on the new transport |
| P2 | Salt Road authored in the Forge, and its voice frozen | validates clean, exports both lanes, C0 differ unchanged, 29 strings ruled by the Director |
| P3 | the diorama — light rig, cast, dressing swap-sets | a re-dress swaps dressing and MOVES NOTHING, asserted position-by-position |
| P4 | the session that binds events to the scene | all three clauses live, and two same-seed runs narrate identically |
| P5 | `node tools/play.mjs` | one command starts the sim, attaches the stage, and cleans up after itself |

---

## 3. The corrections — nine defects in other people's work, found by building a consumer

Each was found because something real had to work, not because a test was added.

### 3.1 `export-godot` could emit a scene Godot refuses to open

`metadata/hidden = ${item.hidden}` was interpolated unguarded. A world omitting that field
produced a `.tscn` whose line 85 read `metadata/hidden = undefined`; Godot answers with a
parse error and drops the **entire scene**. The export reported `success: true`.

The 36-assertion headless engine smoke could not catch it — its proof world authors every
field it touches, so the omitted-field case had never been exported. Fixed at the only
place the text can escape (`assertParseable`), because guarding sites one at a time is how
one gets missed. New suite; the exact defect is the RED control.

### 3.2 The validator passes worlds both exporters crash on

`validateProject` returned `valid: true` for a world with two illegal `EntityRole` values
(`ROLE_TAGS[ep.role] is not iterable`) and an invented `MarketNode` shape (`.slice` of
undefined). Acceptance is not comprehension — C0's finding, one layer up. **Not fixed
here**; named for the Director.

### 3.3 Five required fields the validator does not check

`tilesets`, `tileLayers`, `props`, `propPlacements`, `ambientLayers` are all non-optional
on `WorldProject`, and a world omitting every one validated clean.

### 3.4 The load gate is opt-in, and forgetting is silent

`applyContentPack` runs its four checks only `if (options.gate)`. A pack with a nonsense
top-level key loaded clean. **This one is mine as much as the engine's** — see §5.

### 3.5 Wiring the gate made the forge's normal output unloadable

The first ordinary `export-ai-rpg` product to meet a properly-wired gate was **REFUSED**,
for carrying `items`, `factionPresences`, `pressureHotspots` — the three keys C3 evaluated
and deliberately ruled do-not-map. The gate had two verdicts, carried or fatal, and no way
to say *examined, and deliberately not carried*. `EVALUATED_NOT_MAPPED_KEYS` plus a fourth
`DropReason` is that third verdict.

### 3.6 `world.zone.state.changed` has no reachable producer from play

The sharpest finding, and the one that would have shipped invisibly. Measured: 60 world
ticks move no district metric; **eight rounds of real combat** produce a defeat,
defeat-fallout, a chronicle entry, a rumour and a companion reaction — and zero zone-state
changes. The only caller of `modifyDistrictMetric` positioned to cross a threshold is a
test.

The system is built, persisted, carried on the wire and rendered by the terminal, and
nothing a player can do triggers it: v3.8's "declared and never produced" shape, in the one
event that makes a town visibly change. `--shock` supplies the input an in-game event would
have supplied, host-side, with the sim still deciding every outcome.

### 3.7 `placements[].spawnCondition` has no runtime channel

Authoring `never` to mean "only the anchor puts this person here" is dropped as
`needs-module-vocabulary`. The fiction absorbed it rather than fighting it.

### 3.8 `stateHash` is reproducible by a JavaScript client, and only by one

Its docstring claimed any client could recompute it. Measured false on Godot 4.7 for two
independent reasons: key order (insertion vs sorted) and number form (`5` → `5.0`).
Docstring corrected; the honest alternative (`verify_position`) built.

### 3.9 `ERROR_CODES.ACTION_REJECTED` is declared and produced by nothing

Harmless dead vocabulary — a refusal travels as an `action.rejected` **event**, which is the
right design. Recorded in passing.

---

## 4. `playerTemplate`, and one thing left inconsistent

C3 ruled `playerTemplate` session-scoped "by the same logic as `buildCatalog`". But
`buildCatalog` and `progressionTrees` are both **declared** in the allowlist and reported as
session-scoped drops, while `playerTemplate` is refused. The same class, handled two ways,
so any world authoring a player template is unloadable. Salt Road authors none, so C4 was
not blocked and **did not widen itself to fix it**. Named here.

---

## 5. ⚠ The honesty ledger — thirteen times I was wrong

C0 logged ten, C1 nine, C3 nine. A cycle with none is not a cycle that made none.

1. **I documented a gate and did not execute it.** `--content`'s help text promised "the
   four-check load gate runs BEFORE any mutation" while passing no `options.gate`, so all
   four checks were skipped. Measured by handing it a nonsense key and watching it load
   clean. This is the studio's named `gates_verify_reality_not_attestation` failure,
   committed by the person who had just written the sentence.
2. **Then I fixed it in a way that made it silent.** Declaring the three refused keys in the
   allowlist converted a loud refusal into a silent acceptance — the exact failure the gate
   replaced — and the load report proved it by saying nothing. Both mistakes in order,
   inside one hour.
3. **My first refusal message did not say what was wrong.** `GateResult.report` carries the
   diff-style expected/actual; `errors[]` keeps only message+hint. I printed the wrong one.
4. **The staleness detector cried wolf.** I ruled "same tick, two hashes" as staleness on
   the theory that a deterministic sim cannot describe one tick twice. It can — `tick` is
   not a state version — so the detector fired continuously through healthy sessions.
5. **The transcript's ORDER was not deterministic.** It mixed presenter output (event-ordered)
   with bus diagnostics (frame-timed). The same seeded session produced the same lines in a
   different sequence on Linux than on Windows. CI caught it; my machine never would have.
6. **The re-dress hit every zone.** `world.zone.state.changed` names ONE zone; my dressing
   system toggled groups tree-wide, so shocking the Long Quay put rubble in all six rooms.
   **Found by looking at the screenshot. 52 green tests said nothing.**
7. **A vacuous visibility assertion.** The test checked `.visible` — a node's own flag —
   while the parent container was hidden, certifying rubble nobody could see.
   `is_visible_in_tree()` is the actual question.
8. **Direction bucketing was mirrored.** The pack's list runs clockwise in screen space, so
   `atan2(y, x)` needs no flip; my negation swapped every left and right while front and
   back stayed correct. Caught only because the test asserts all eight compass points — a
   character facing 45° wrong looks deliberate.
9. **The runner reported PASS over a test file that never ran.** A script that fails to
   compile still loads non-null; `new()` errored, the function bailed before the
   "asserted nothing" guard, and the verdict was `checks=0 failed=0 verdict=PASS` — a
   vacuous pass inside the runner built to refuse vacuous passes.
10. **An un-awaited coroutine truncated silently, twice.** `_redress_swaps_without_moving`
    waits on frames; called bare it returned at its first await and the suite reported
    43/43 PASS while its load-bearing assertion was unreachable. There is a section canary
    now, proven to fire.
11. **`equals` with four arguments** aborted a test function mid-way, which is how the
    "moved NOTHING" assertion went missing while the suite said PASS.
12. **`dogfood/` is in no tsconfig, and it cost four defects in one phase**: a read of
    `zone.entryGate` on a type with no such field (printing `gates 0` for a world authoring
    three), two illegal `EntityRole`s, an invented `MarketNode` shape, and a missing
    required `hidden`. Adding a scoped typecheck immediately found two more —
    `packFormatVersion` (the field is `formatVersion`) and `zone.name` (it is `displayName`)
    — both silently emitting nothing into every fixture generated to that point.
13. **I fixed one site and missed its sibling.** The fixture generator's `gatedZones` count
    had the same nonexistent-`entryGate` bug as the log line I had just repaired, and
    emitted 0 for a world with a gate.

**And three diagnoses I asserted and then had to withdraw:**

- The CI gate failure was NOT EPIPE-under-pipefail. I named that cause confidently, tested
  it, and it was refuted: node exits 0 on an early pipe close and `--help` never calls
  `process.exit`. The comment in CI now records the observation and names the refuted theory
  rather than a cause I could not reproduce.
- The connection-cap injection proof was **contaminated on the first attempt**: run with
  `-t`, the setup test is skipped, so the red I saw proved nothing about the cap.
- I assumed three event-contract names and payload keys and was wrong about all three
  (`world.zone.gate.refused` not `gate.refused`; `spawnedEntityIds` not `entityIds`; the
  shock moves BOTH zones of a district, not one).

**Process note:** every phase boundary ran the full stage lists in all three repos. The
engine's suite went red once, on a C1 pin I had deliberately invalidated, and the pin was
flipped in the same commit per the arc's law.

---

## 6. Determinism (charter §6.1)

| Path | Control |
|---|---|
| the wire, three transports | one session byte-identical in-process, over stdio, over TCP |
| the stage's received bytes | two same-seed sessions receive byte-identical frames |
| the transcript | two same-seed sessions narrate identically, with a RED control |
| the re-dress | idempotent (re-applying a state changes nothing) and reversible |
| the rubble | deterministic geometry, no `Math.random` anywhere in the cycle's code |

**Which hash, stated:** state-hash, not screenshot-hash. Presentation timing is wall-clock
by design — juice is client-side — so a pixel comparison would measure frame scheduling.
What is compared is the simulation's own bytes and the stage's own transcript.

---

## 7. Carried and honestly inert — what does NOT work yet

| Thing | State |
|---|---|
| the shock's cause | a host-side scenario cue, because nothing in play produces one (§3.6) |
| the cast | one good fit and four compromises; the pack is a fantasy VILLAGE roster and this is a mercantile harbour |
| floors and props | client-side placeholders — flat colour and blocks. Real art comes from the spine |
| the tileset | a procedurally generated placeholder atlas, deterministic so it does not churn |
| `playerTemplate` | still refused by the allowlist (§4) |
| the SubViewport composite | recorded as the preserved upgrade path, not built |
| combat staging, Motif binding | C5 and C6; untouched |

---

## 8. The jury (EXTERNAL_VERIFIER)

C3 scored this **1** and named remediation. It ran.

**Ollama Cloud was unreachable** — `auth: unverified`, and a probe call fell back to local
`hermes3:8b` while disclosing it. So the panel is the free local cross-family trio, the
testing-os precedent: `mistral-small:24b` (Mistral), `granite4.1:30b` (IBM),
`gemma4:31b` (Google). Three disjoint families, none Claude, each served model verified
against the request. Reported as the fallback it is, not as the cloud flagships.

Eight falsifiable claims, reasoning stripped, with measured evidence attached.
**7 CONFIRMED, 1 NEEDS_REVIEW**, lone-dissent-never-decides:

- **C5 (the forge export was refused) → NEEDS_REVIEW**, and the panel was right. Both
  dissents made the same point: the evidence line showed a refusal for those keys but never
  established that the refused pack was `export-ai-rpg`'s *ordinary product*. The claim is
  true and I have the proof — the sidecar was pointed at the file
  `exportToEngine(saltRoadProject)` writes — but I did not put it in the packet. A verifier
  withholding on an evidence gap is the verifier working.
- ⚠ **A juror mislabelled itself.** On C8, mistral's rationale ("Evidence shows entity was
  placed despite spawnCondition:'never'") *agrees* with the claim while its label says
  REFUTE. Counted as the dissent it declared rather than as the confirm it argued, because
  re-reading a juror's vote in the direction you wanted is how a panel stops being external.

---

## 9. Standards compliance

- **PIN_PER_STEP — 2.** SHAs pinned and re-verified at HEAD; every probe seeded (71, plus
  a named `FIRING_SEED` where a probabilistic gate needed one); Godot pinned to 4.7-stable
  in CI rather than floating. Not 3: no byte-replayable dispatch lock for the phases.
- **ANDON_AUTHORITY — 3.** Four halts called rather than worked around: the `dogfood/`
  typecheck scoped to two files instead of fixing five unrelated pre-existing failures; the
  canonical cross-language hash routed to the Director instead of built; `playerTemplate`
  named instead of widened into; the validator gap recorded instead of fixed.
- **NAMED_COMPENSATORS — 3.** Table below. Nothing irreversible performed. Repo creation
  compensated by archive, never deletion.
- **DECOMPOSE_BY_SECRETS — 3.** Three repos, three secrets: the client owns coordinates,
  light and dressing; the engine owns rules and the wire; the forge owns authoring and
  export. The one place they meet — the zone id — has a joiner and a both-directions proof.
- **UNCERTAINTY_GATED_HUMANS — 3.** Two genuine checkpoints, both gating on real
  uncertainty rather than on step count: the **voice gate** (29 strings, Director ruled
  "freeze it") and the **canonical-hash fork** (framed contrastively with a recommendation;
  the Director ANDON'd it and supplied the design note for the future slice).
- **EXTERNAL_VERIFIER — 2.** The jury ran, cross-family, floor-primary, advisory, with its
  degraded transport disclosed and one dissent honoured. Not 3: the panel is the local
  fallback rather than the cloud flagships, and one juror mislabelled a vote.

---

## 10. Compensators

| Action | Undo | Owner |
|---|---|---|
| CREATED `mcp-tool-shop-org/ai-rpg-stage` | `gh repo archive mcp-tool-shop-org/ai-rpg-stage` — **never delete** | executor |
| Branch `feat/c4-wire-and-diorama` (stage) | `git push origin --delete feat/c4-wire-and-diorama` | executor |
| Branch `feat/c4-socket-attach` (engine) | `git push origin --delete feat/c4-socket-attach` | executor |
| Branch `feat/c4-stage-lane` (forge) | `git push origin --delete feat/c4-stage-lane` | executor |
| Production commits | `git revert` per slice | executor |
| PRs | close unmerged | executor |

No publish, no tag, no version bump, no deploy, no deletion. Versions remain 3.8.0 / 4.5.0;
the stage is unversioned and unpublished. Merge is the advisor's gate.

---

## 11. How to play it

```bash
node tools/play.mjs
```

Requires Godot 4.7.x on `PATH` (or `GODOT_BIN`), a built engine checkout and an exported
Salt Road. Every precondition failure prints the command that fixes it.

Number keys walk you through the door with that number. Space waits a round — which is how
the shock reaches you. Escape leaves.

**Walk to the Bonded Warehouse without the seal.** That is the beat this whole rung was
built to deliver.

---

Related: [[ai-rpg-engine-2p5d-quality-bar]] (§5 row C4), [[2p5d-c3-space-vocabulary-complete]]
(the three transcripts this made visible), [[2p5d-c1-contract-v1-complete]] (the wire),
[[feedback_human_layer_prose]] (binding; the voice is frozen),
[[feedback_marathon_not_sprint]], [[feedback_infrastructure_is_not_a_game]] (the
discriminator), [[feedback_a_consumer_finds_what_the_producer_cannot]],
[[cross-family-cloud-verification]], [[workflow-standards]].
