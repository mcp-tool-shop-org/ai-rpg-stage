#!/usr/bin/env bash
# verify.sh — test + build + smoke in one command (Ship Gate D1).
#
#   ./verify.sh            import, run the headless suite, gate every runtime plate, build the site if present
#   ./verify.sh --quick    skip the site build
#
# Requires Godot 4.7.x on PATH as `godot`, Python 3 with numpy + Pillow for the ANDON,
# and Node 20+ only if site/ exists. The engine is NOT required: the suites that need a
# live sim resolve it from AI_RPG_ENGINE_DIR or a sibling ../ai-rpg-engine and skip with
# a named reason when neither is present.
set -euo pipefail
cd "$(dirname "$0")"

quick=0
for a in "$@"; do [ "$a" = "--quick" ] && quick=1; done

step() { printf '\n\033[1m› %s\033[0m\n' "$*"; }

step "godot version (must be 4.7.x)"
godot --version | tee /tmp/ai-rpg-stage-godot.txt
grep -q '^4\.7\.' /tmp/ai-rpg-stage-godot.txt || { echo "::error::Godot is not 4.7.x"; exit 2; }

step "import project (populates .godot/)"
godot --headless --path . --import >/dev/null 2>&1 || true

step "headless suite"
godot --headless --path . --script res://tools/headless.gd 2>&1 | tee /tmp/ai-rpg-stage-suite.log
grep -q '^verdict=PASS' /tmp/ai-rpg-stage-suite.log || { echo "::error::headless suite reported failure"; exit 1; }
if grep -Eq 'SCRIPT ERROR|Failed loading resource|Cannot open file|Condition ".*" is true' /tmp/ai-rpg-stage-suite.log; then
  echo "::error::engine reported load errors during the suite"; exit 1
fi

step "ANDON: every runtime plate in assets/dimetric/MANIFEST.json still passes"
python - <<'PY'
import json, subprocess, sys, os
root = "assets/dimetric"
man = json.load(open(os.path.join(root, "MANIFEST.json"), encoding="utf-8"))
bad = []
for e in man["entries"]:
    if e.get("phase", 0) == 0 or e["andon"] != "pass":
        continue
    fp = ",".join(str(x) for x in e.get("footprint", [1, 1]))
    cmd = [sys.executable, os.path.join(root, "andon", "iso_andon.py"), os.path.join(root, e["path"]),
           "--kind", e["kind"], "--footprint", fp, "--json", os.devnull]
    r = subprocess.run(cmd, capture_output=True, text=True)
    status = "PASS" if r.returncode == 0 else "FAIL"
    print(f"  {status}  {e['id']}")
    if r.returncode != 0:
        bad.append(e["id"])
if bad:
    print("::error::plates failing the ANDON: " + ", ".join(bad)); sys.exit(1)
PY

if [ "$quick" = "0" ] && [ -f site/package.json ]; then
  step "site build (landing + handbook + pagefind)"
  (cd site && npm ci --silent && npm run build --silent)
  test -f site/dist/index.html || { echo "::error::landing page did not build"; exit 1; }
  test -f site/dist/handbook/index.html || { echo "::error::handbook did not build"; exit 1; }
  ls site/dist/pagefind/pagefind.js >/dev/null 2>&1 || ls site/dist/_pagefind/pagefind.js >/dev/null 2>&1 \
    || { echo "::error::pagefind index missing"; exit 1; }
fi

step "verify: OK"
