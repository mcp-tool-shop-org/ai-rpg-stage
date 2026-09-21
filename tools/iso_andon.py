#!/usr/bin/env python3
"""Shim. The canonical ANDON is assets/dimetric/andon/iso_andon.py.

MANIFEST.json points there. This file exists so `python tools/iso_andon.py`
from the repo root still hits the same gates (RGBA, 26.565°, checker, corners).
Do not add a second implementation here.
"""
from __future__ import annotations

import runpy
import sys
from pathlib import Path

CANON = Path(__file__).resolve().parents[1] / "assets" / "dimetric" / "andon" / "iso_andon.py"
if not CANON.is_file():
    sys.exit(f"canonical ANDON missing: {CANON}")
sys.argv[0] = str(CANON)
runpy.run_path(str(CANON), run_name="__main__")
