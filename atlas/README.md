# ai-rpg-stage: how it works

Mapped at 2026-11-24 from commit 1d9ac5b by Atlas 1.26.0.

## What this is

12 parts, mostly GDScript (39 files), Python (8), JavaScript (3), CSS (2), TypeScript (2), shell (2) and Astro (1). Work enters through 4 doors; the busiest is ci, which reaches 5 parts. It deploys a site to GitHub Pages. People run the game.

## What changed since 2026-11-24 (1e691c0)

- ci now also runs tests/test_profile_policy.gd and tools/check_ci_log.sh.
- stage/ is now read by stage/playable.gd.
- tools/ is now read by tools/sidecar_harness.gd.
- 6 files added and 9 changed content, across 7 parts.

## What comes in

1. **ci.** On a pull request touching 12 paths; on a push touching 12 paths; or by hand. On a push, or a pull request from a fork, it runs tools/check_ci_log.sh and tools/headless.gd, which runs the 13 test suites under tests/ it finds at run time.
2. **Deploy site to GitHub Pages.** On a push to main touching 2 paths; or by hand. Runs site/astro.config.mjs and site/src/.
3. **Bump upstream pins.** On a schedule (`0 7 * * 1`), Monday at 07:00 UTC; or by hand. Runs no file this map can see.
4. **the game** (what Godot runs). Starts stage/diorama.tscn.

## What happens through ci

1. On a push, or a pull request from a fork, it runs tools/check_ci_log.sh and tools/headless.gd, which runs the 13 test suites under tests/ it finds at run time.
2. That reaches client (6 files) and stage (15 files).
3. That reaches fixtures (1 file).
4. It writes to fixtures/.

## Who reads the results

- **fixtures/** is read by stage/diorama.gd, stage/iso/iso_world.gd and tools/play.mjs, and by 2 tests.

## The other doors

**Deploy site to GitHub Pages** runs site/astro.config.mjs and site/src/, and deploys the site.

**Bump upstream pins** runs no file this map can see, writes to .github/upstream-pins.env, commits .github/upstream-pins.env and pushes to a branch for review, never to main, opens an issue, and reads other repositories through the GitHub API.

**the game** (what Godot runs) starts stage/diorama.tscn and reaches client and fixtures.

## What breaks what

- **client** is imported by 1 part (stage), and by 1 more only from tests; it sits on the path of 2 doors.
- **stage** is imported by 1 part (tools), and by 1 more only from tests; it sits on the path of 2 doors.
- **fixtures** is imported by 1 part (stage) and sits on the path of 2 doors.
- **tools** is imported only from tests, by 1 part (tests), and sits on the path of 1 door.
- **fixtures/** is written by .github and read by stage and tools, and by 2 tests; a hand edit reaches every reader.

## What tends to change together

No two source files changed together often enough to name.

Window: 180 days; a pair counts from 3 shared commits, since 0 source files reach 10 revisions; the floor rises to 10 when 25 do.

## What no test touches

- **assets** is imported by no test.

verify.sh runs in no workflow.

## Written but never read

- **assets/dimetric/MANIFEST.json** is written by assets/dimetric/andon/build_manifest.py and read by nothing else in this repository.

## Helpers that look duplicated

No two parts export a helper that looks alike.

## Generated, never hand-edited

- **assets/dimetric/MANIFEST.json** is written by assets/dimetric/andon/build_manifest.py.
- **assets/felt/MANIFEST.json** is written by assets/felt/synth_felt_pack.py.
- **fixtures/** is written by .github/workflows/ci.yml.

## Hand-authored

People write audio/, docs/, the repository root and site/; 3 writes with paths built at run time may land here.

- **.github/upstream-pins.env** is written by .github/workflows/bump-upstream-pins.yml, and by people: 7 of its 7 commits in the window are theirs.

## Where to start

.github/workflows/ci.yml → tools/headless.gd → tools/test_case.gd

Read those in order to follow one push, or pull request from a fork, end to end.

## What this map cannot see

- 3 writes and 12 reads use paths built at run time and are not named here.
- 4 writes go to places this repository does not track, so they are not listed as generated.
- 5 writes and 3 reads go to a path their caller passes, not to this repository.
- 2 writes go to a temporary directory, not to this repository.
- 3 commands are built at run time and not followed.
- Statistics confidence is low: fewer than 25 source files reach 10 revisions in the window.

Regenerate with `npx --yes @dogfood-lab/atlas map`.
