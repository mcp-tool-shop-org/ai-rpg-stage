# Scorecard

> Score a repo before remediation. Fill this out first, then use SHIP_GATE.md to fix.

**Repo:** ai-rpg-stage
**Date:** 2026-09-21
**Type tags:** `[all]` `[desktop]` (Godot 4.7 client run from source; not npm, not CLI, not MCP)

## Pre-Remediation Assessment

| Category | Score | Notes |
|----------|-------|-------|
| A. Security | 7/10 | SECURITY.md complete with contact, scope, and trust boundary. README had no threat-model section (Gate K failed on A2). No telemetry, no secrets, one outbound socket. |
| B. Error Handling | 7/10 | Staleness and transport faults are sentences on the status line and in the log; `play.mjs` prints the fixing command. No structured `code` field on the stage's own notices (the engine's JSON-RPC errors carry one). |
| C. Operator Docs | 6/10 | README current and honest about the join and the doctored fixture, but no keys table, no `play.mjs` flags, no threat model, no support status. CHANGELOG and LICENSE present. |
| D. Shipping Hygiene | 4/10 | No `verify` script, no version in `project.godot`, no tag, CI suite manifest listed six of eleven suites. Upstream pins are bumped weekly (good). |
| E. Identity (soft) | 0/10 | No logo, no translations, no landing page, no handbook, no repo metadata. |
| **Overall** | **24/50** | |

## Key Gaps

1. README lacked a trust/threat-model section (A2, executed gate failed) and any statement about telemetry or support status.
2. No single `verify` command; CI's "every expected suite ran" manifest had drifted to six names while eleven suites exist, so five suites could vanish unnoticed.
3. No public surfaces at all: logo, landing page, handbook, translations, GitHub metadata.
4. Tracked files carried local drive paths (ANDON docstring, every render.json `out` field).

## Remediation Priority

1. Gate A/C in the README (threat model, telemetry, status, keys, flags) and `verify.sh` (D1); fix the CI suite manifest; scrub drive paths.
2. Logo to brand, README badges, translations.
3. Landing page + handbook (amber), GitHub metadata, repo-knowledge entry.

## Post-Remediation (0.2.0, 2026-09-21)

`npx @mcptoolshop/shipcheck audit`: **20 checked, 0 unchecked, 19 SKIP, 100%** — all hard gates pass.
The SKIPs are the npm / PyPI / CLI / MCP / VS Code rows a Godot client has no surface for, plus the
tag row, which re-checks on the first tag.

| Category | Score | What closed it |
|----------|-------|----------------|
| A. Security | 10/10 | Threat model, telemetry statement, and trust boundary are in the README beside SECURITY.md. |
| B. Error Handling | 8/10 | Staleness, transport faults and refusals are plain sentences on the status line and in the log; the engine's JSON-RPC errors keep their codes. The stage's own notices still carry no `code` field. |
| C. Operator Docs | 10/10 | README carries the keys table, `play.mjs` flags, the join, the threat model and the support status; landing page and five-page handbook are live. |
| D. Shipping Hygiene | 9/10 | `verify.sh` (import → 273 checks → plate re-gate → site build), `config/version="0.2.0"`, CI suite manifest at eleven of eleven, upstream pins bumped weekly and pinned to engine 3.12.0. No tag yet — held for release. |
| E. Identity | 10/10 | Logo, eight-language README set, landing page, Starlight handbook, GitHub metadata. |
| **Overall** | **47/50** | |

Open, and deliberately so: no structured `code` on the stage's own notices, and no export preset —
the stage runs from source under Godot 4.7 until an export is a release decision.
