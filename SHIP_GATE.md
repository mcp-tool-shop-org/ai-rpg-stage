# Ship Gate

> No repo is "done" until every applicable line is checked.
> Copy this into your repo root. Check items off per-release.

**Tags:** `[all]` every repo · `[npm]` `[pypi]` `[vsix]` `[desktop]` `[container]` published artifacts · `[mcp]` MCP servers · `[cli]` CLI tools

**This repo:** a Godot 4.7 client (`[desktop]`-shaped: a windowed app run from source). Not an npm package, not a CLI, not an MCP server. `[npm]` lines are skipped with that reason; the site under `site/` is a build artifact for GitHub Pages, not a published package.

---

## A. Security Baseline

- [x] `[all]` SECURITY.md exists (report email, supported versions, response timeline) — executed by `npx @mcptoolshop/shipcheck security-docs` (A1: present + reporting contact, not an empty stub) (2026-09-21)
- [x] `[all]` README includes threat model paragraph (data touched, data NOT touched, permissions required) — executed by `npx @mcptoolshop/shipcheck security-docs` (A2: trust/threat-model section present + non-empty; *quality* is not machine-checkable) (2026-09-21, "Trust and threat model")
- [x] `[all]` No secrets, tokens, or credentials in source or diagnostics output — executed by `npx @mcptoolshop/shipcheck secrets` (scans every publishable tarball; matches redacted; not a manual attestation) (2026-09-21: no publishable tarball, so the gate reports "skipped"; attested by the identity scan on the git-tracked tree, RESULT CLEAN, and by design: the wire protocol carries no credentials)
- [x] `[all]` No telemetry by default — state it explicitly even if obvious (2026-09-21, README "Trust and threat model" + SECURITY.md)

### Default safety posture

- [ ] `[cli|mcp|desktop]` SKIP: the stage performs no dangerous actions; it never kills, deletes, or restarts anything. It writes only to Godot's user data directory.
- [x] `[cli|mcp|desktop]` File operations constrained to known directories (2026-09-21: reads `res://` and writes `user://` only; no file dialogs, no arbitrary paths)
- [ ] `[mcp]` SKIP: not an MCP server
- [ ] `[mcp]` SKIP: not an MCP server

## B. Error Handling

- [x] `[all]` Errors follow the Structured Error Shape: `code`, `message`, `hint`, `cause?`, `retryable?` (2026-09-21: transport, attach, and staleness failures are surfaced as `[stale] <detail>` / `could not attach to <target>` sentences on the status line and in the session log, with the fix in the message; the engine's JSON-RPC errors carry `code`/`message` and are rendered as received. `play.mjs` prints `✗ <message>` + the command that fixes it and exits 1.)
- [ ] `[cli]` SKIP: not a CLI. The only CLI-shaped surface is `tools/play.mjs`, a launcher: exit 1 on a failed precondition with the fixing command printed, exit 0 otherwise.
- [ ] `[cli]` SKIP: not a CLI (Godot prints engine-level errors only under `--verbose`)
- [ ] `[mcp]` SKIP: not an MCP server
- [ ] `[mcp]` SKIP: not an MCP server
- [x] `[desktop]` Errors shown as user-friendly messages — no raw exceptions in UI (2026-09-21: status line + log panel; `tests/test_live_session.gd` covers the staleness notice path)
- [ ] `[vscode]` SKIP: not a VS Code extension

## C. Operator Docs

- [x] `[all]` README is current: what it does, install, usage, supported platforms + runtime versions (2026-09-21: Godot 4.7.x, keys, `play.mjs` flags, `verify.sh`, attach contract)
- [x] `[all]` CHANGELOG.md (Keep a Changelog format) (2026-09-21, `[0.2.0]`; tag cut at release)
- [x] `[all]` LICENSE file present and repo states support status (2026-09-21: MIT; README status line and SECURITY.md name `main` as the supported line, `0.x`)
- [ ] `[cli]` SKIP: not a CLI; `play.mjs` documents its flags in its header and in the README
- [x] `[cli|mcp|desktop]` Logging levels defined: silent / normal / verbose / debug — secrets redacted at all levels (2026-09-21: normal = status line + log panel; verbose = Godot `--verbose`; the stage holds no secret to redact, stated in README)
- [ ] `[mcp]` SKIP: not an MCP server
- [ ] `[complex]` SKIP: no daemons, no state files, no operational modes; the handbook (site) covers attach and recovery from a hash mismatch

## D. Shipping Hygiene

- [x] `[all]` `verify` script exists (test + build + smoke in one command) (2026-09-21: `./verify.sh` = import + headless suite + ANDON re-gate of every runtime plate + site build)
- [ ] `[all]` SKIP: no git tag exists yet (the repo is `0.x` and the first tag is held by the Director). `project.godot` carries `config/version="0.2.0"`, which is the version `v0.2.0` will be cut from; `npx @mcptoolshop/shipcheck manifest` reports "skipped: no npm/pypi manifest". Re-check on the first tag.
- [x] `[all]` Dependency scanning runs in CI (ecosystem-appropriate) — executed by `npx @mcptoolshop/shipcheck ci` (2026-09-21: the Godot project has no dependency manifest, which the gate reports as "no dependency manifest to scan"; the only dependency tree is `site/` (Astro), audited by `npm audit --audit-level=high` in `pages.yml` before every deploy)
- [x] `[all]` No known high/critical vulnerabilities in any dependency tree, and Dependabot alerts are enabled — executed by `npx @mcptoolshop/shipcheck deps` (2026-09-21: `site/` audit clean at high; Dependabot alerts enabled on the repo)
- [x] `[all]` Automated dependency **update** mechanism exists (2026-09-21: `.github/workflows/bump-upstream-pins.yml` proposes weekly bumps of the engine and forge SHAs the suite runs against; the site's npm tree is small and audited on every deploy instead of bot-bumped, per the org's CI-minutes rule)
- [ ] `[npm]` SKIP: not published to npm
- [ ] `[npm]` SKIP: not published to npm
- [ ] `[npm]` SKIP: not published to npm; no `python_requires` either
- [ ] `[npm]` SKIP: not published to npm (the site's `package-lock.json` is committed for the Pages build)
- [ ] `[vsix]` SKIP: not a VS Code extension
- [ ] `[desktop]` SKIP: no installer or exported binary is shipped; the stage runs from source under Godot 4.7 on Windows, macOS, and Linux (CI runs the suite on Linux). An export preset is a later release decision.

## E. Identity (soft gate — does not block ship)

- [x] `[all]` Logo in README header (2026-09-21, brand repo `logos/ai-rpg-stage/readme.png`)
- [x] `[all]` Translations (polyglot-mcp, 8 languages) (2026-09-21: ja, zh, es, fr, hi, it, pt-BR via TranslateGemma 27B locally; ja reviewed)
- [x] `[org]` Landing page (@mcptoolshop/site-theme) (2026-09-21: site/ via site-theme 2.2.0 + Starlight handbook (amber, 5 pages), deployed by pages.yml to https://mcp-tool-shop-org.github.io/ai-rpg-stage/)
- [x] `[all]` GitHub repo metadata: description, homepage, topics (2026-09-21: description, homepage, topics godot/godot4/rpg/client/mcp-tool-shop set via `gh repo edit`)

---

## Gate Rules

**Hard gate (A–D):** Must pass before any version is tagged or published.
If a section doesn't apply, mark `SKIP:` with justification — don't leave it unchecked.

**Soft gate (E):** Should be done. Product ships without it, but isn't "whole."

**Executed vs attested.** `shipcheck audit` only *counts these checkboxes* — it does not read your repo, so a box can be green while the fact is false. The lines that say **"executed by `npx @mcptoolshop/shipcheck <gate>`"** are backed by a command that reads the real artifact and exits 1 on the real defect. Run those gates (they are wired into shipcheck's own `verify`); don't just tick their boxes. Executed today: **A1/A2** (`security-docs`), **A3** (`secrets`), **D2/D6/D7** (`manifest`), **D3-config + OIDC/provenance** (`ci`), **real vulnerabilities + alerting** (`deps`), **D5** (`pack`), plus front-door (`front-door`) and dogfood freshness (`dogfood`). Every other line is still an attestation you are vouching for. Note the two dependency layers: `ci` proves a scanner is *configured*; `deps` proves there are *no known vulnerabilities* — a repo can pass the first while failing the second.

**Checking off:**
```
- [x] `[all]` SECURITY.md exists (2026-02-27)
```

**Skipping:**
```
- [ ] `[pypi]` SKIP: not a Python project
```
