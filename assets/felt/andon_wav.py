#!/usr/bin/env python3
"""andon_wav.py — refuse a felt pack that would play wrong.

    python assets/felt/andon_wav.py            (checks MANIFEST.json + every wav beside this file)

Exit 1 on: a required CORE_SOUND_PACK id missing; a manifest entry whose file is missing; stereo;
not 16-bit; duration out of band for its role (stem/bed >= 6 s, sting 0.4–2 s, ui <= 0.3 s,
alert <= 1.5 s); peak below -40 dBFS (silence); peak at full scale on more than 0.1% of samples
(clipping); DC offset above 2% of full scale; a loop whose wrap point jumps more than 0.05 full-scale AND more than 4x the file's median sample step (a click; noise beds step that much everywhere). Prints one line per file with the measured numbers.
Stems and beds must be distinguishable from each other by spectral centroid (dread vs calm) —
measured, not asserted.
"""
from __future__ import annotations

import json
import math
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REQUIRED = ["music_dread", "ambient_drone", "music_calm", "ambient_white_noise",
            "music_victory_sting", "music_defeat_sting", "music_retreat_sting", "ui_click", "alert_warning"]
BANDS = {"stem": (6.0, 60.0), "bed": (6.0, 60.0), "sting": (0.4, 2.0), "ui": (0.0, 0.3), "alert": (0.0, 1.5)}


def read(path: str):
    with wave.open(path, "rb") as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    x = np.frombuffer(raw, dtype="<i2").astype(float) / 32768.0 if sw == 2 else None
    return ch, sw, sr, n, x


def centroid(x: np.ndarray, sr: int) -> float:
    seg = x[: min(len(x), sr * 4)]
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
    freqs = np.fft.rfftfreq(len(seg), 1.0 / sr)
    return float((spec * freqs).sum() / (spec.sum() + 1e-12))


def main() -> int:
    man_path = os.path.join(HERE, "MANIFEST.json")
    if not os.path.isfile(man_path):
        print("FAIL no MANIFEST.json"); return 1
    man = json.load(open(man_path, encoding="utf-8"))
    ids = {e["id"]: e for e in man.get("entries", [])}
    fails = []
    for r in REQUIRED:
        if r not in ids:
            fails.append(f"required id missing from manifest: {r}")
    cents = {}
    for e in man.get("entries", []):
        p = os.path.join(HERE, e["path"])
        if not os.path.isfile(p):
            fails.append(f"{e['id']}: file missing {e['path']}"); continue
        ch, sw, sr, n, x = read(p)
        dur = n / sr
        peak_db = 20 * math.log10(max(float(np.max(np.abs(x))), 1e-9)) if x is not None else -200
        clip = float(np.mean(np.abs(x) >= 0.9995)) if x is not None else 0
        dc = float(abs(x.mean())) if x is not None else 0
        cen = centroid(x, sr) if x is not None else 0
        cents[e["id"]] = cen
        lo, hi = BANDS.get(e.get("role", "stem"), (0, 60))
        problems = []
        if ch != 1: problems.append(f"channels={ch}")
        if sw != 2: problems.append(f"bits={sw*8}")
        if sr not in (22050, 44100): problems.append(f"rate={sr}")
        if not (lo <= dur <= hi): problems.append(f"duration {dur:.2f}s outside {lo}-{hi}")
        if peak_db < -40: problems.append(f"peak {peak_db:.1f} dBFS (silence)")
        if clip > 0.001: problems.append(f"clipping {clip*100:.2f}%")
        if dc > 0.02: problems.append(f"dc offset {dc:.3f}")
        # Loop seam: the wrap jump measured against the file's own typical sample-to-sample step, so a
        # noise bed (large steps everywhere) is judged fairly and a drone with a phase jump is caught.
        seam = float(abs(x[-1] - x[0])) if (x is not None and e.get("loop")) else 0.0
        step = float(np.median(np.abs(np.diff(x)))) + 1e-6 if x is not None else 1.0
        seam_ratio = seam / step if e.get("loop") else 0.0
        if e.get("loop") and seam > 0.05 and seam_ratio > 4.0:
            problems.append(f"loop seam jump {seam:.3f} = {seam_ratio:.0f}x the typical step (click)")
        status = "ok  " if not problems else "FAIL"
        print(f"{status} {e['id']:24s} {e.get('role','?'):6s} {dur:6.3f}s peak {peak_db:6.1f} dBFS  centroid {cen:7.0f} Hz  dc {dc:.4f}  seam {seam:.3f} ({seam_ratio:.1f}x step)")
        if problems:
            fails.append(f"{e['id']}: " + "; ".join(problems))
    # distinguishability: dread must sit well below calm; a sting must be shorter than every stem
    if "music_dread" in cents and "music_calm" in cents:
        if not cents["music_calm"] > cents["music_dread"] * 1.5:
            fails.append(f"music_calm centroid {cents['music_calm']:.0f} Hz is not > 1.5x music_dread {cents['music_dread']:.0f} Hz")
    stems = [ids[i]["seconds"] for i in ids if ids[i].get("role") in ("stem", "bed")]
    stings = [ids[i]["seconds"] for i in ids if ids[i].get("role") == "sting"]
    if stems and stings and not max(stings) < min(stems):
        fails.append("a sting is not shorter than every stem")
    for f in fails:
        print("::error::", f)
    print("RESULT", "PASS" if not fails else f"FAIL ({len(fails)})")
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
