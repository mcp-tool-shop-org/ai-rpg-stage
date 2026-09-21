#!/usr/bin/env python3
"""synth_felt_pack.py — grey-box audio for the CORE_SOUND_PACK cue ids, local numpy only.

    python assets/felt/synth_felt_pack.py          (writes <id>.wav + MANIFEST.json beside this file)

These are stand-ins that match the grey-box plates: filtered noise, drones, short rising/falling
stings. They exist so the cue-id contract (stem / bed / sting / ui / alert) is audible as different
things, not as sine beeps. Filenames ARE the cue ids from ai-rpg-engine's soundpack-core
`CORE_SOUND_PACK`; nothing here invents an id. 16-bit PCM mono, 44.1 kHz, loops are seamless
(period-exact) and peak-normalised to -3 dBFS with a DC block.
"""
from __future__ import annotations

import json
import math
import os
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(71)  # the seed every proof in the repo uses


def t(seconds: float) -> np.ndarray:
    return np.arange(int(round(seconds * SR))) / SR


def env(n: int, attack: float, release: float) -> np.ndarray:
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[-r:] = np.linspace(1, 0, r)
    return e


def lowpass(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    """One-pole IIR applied `order` times (no scipy)."""
    rc = 1.0 / (2 * math.pi * cutoff)
    alpha = (1.0 / SR) / (rc + 1.0 / SR)
    y = x.copy()
    for _ in range(order):
        out = np.empty_like(y)
        acc = 0.0
        for i, v in enumerate(y):
            acc += alpha * (v - acc)
            out[i] = acc
        y = out
    return y


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass(x, cutoff, 1)


def make_loop(y: np.ndarray, n: int, fade_s: float = 0.25) -> np.ndarray:
    """Cut a seamless n-sample loop from a longer signal y (len >= n + fade).

    The seam is where sample n-1 is followed by sample 0. Playing y[n-1] then y[0] jumps, so the
    START of the loop is rebuilt as a crossfade from the tail's natural continuation y[n:n+fade]
    into the true head y[0:fade]: at the wrap the signal continues as recorded, then eases into
    the head over `fade`. (The earlier version blended the tail into the head, which made the last
    sample land on y[fade-1] and still jump to y[0]: measured 0.23 full-scale at the seam.)"""
    fade = int(fade_s * SR)
    loop = y[:n].copy()
    r = np.linspace(0.0, 1.0, fade)
    loop[:fade] = y[n:n + fade] * (1.0 - r) + y[:fade] * r
    return loop


def loop_noise(seconds: float, cutoff: float, gain: float) -> np.ndarray:
    """Seamless filtered-noise loop."""
    n = int(seconds * SR)
    y = lowpass(rng.standard_normal(n + 2 * SR), cutoff, 3)[SR:]
    return make_loop(y, n) * gain


def drone(seconds: float, freqs: list[float], detune: float, wobble_hz: float) -> np.ndarray:
    """Period-exact drone: every partial is rounded to an integer number of cycles so the loop is seamless."""
    tt = t(seconds)
    out = np.zeros_like(tt)
    w_exact = round(wobble_hz * seconds) / seconds          # integer cycles of vibrato per loop
    for i, f in enumerate(freqs):
        cycles = round(f * seconds)
        f_exact = cycles / seconds
        # ADDITIVE vibrato: phase = 2π f t + depth·sin(2π w t + i). Both terms return to their start
        # value at t = seconds, so the loop is seamless. (Multiplying the phase by (1 + d·sin) left the
        # wrap off by 2π·cycles·d·sin(i): a measured 0.22 full-scale click.)
        depth = detune * 40.0
        out += np.sin(2 * math.pi * f_exact * tt + depth * np.sin(2 * math.pi * w_exact * tt + i)) / (i + 1)
    return out


def sting(seconds: float, f0: float, f1: float, kind: str) -> np.ndarray:
    tt = t(seconds)
    n = len(tt)
    freq = f0 * (f1 / f0) ** (tt / seconds)            # exponential glide f0 -> f1
    phase = 2 * math.pi * np.cumsum(freq) / SR
    x = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.15 * np.sin(3 * phase)
    if kind == "bright":
        x += 0.25 * highpass(rng.standard_normal(n), 3000) * env(n, 0.005, seconds * 0.6)
    e = env(n, 0.01, seconds * 0.7)
    return x * e


def normalise(x: np.ndarray, dbfs: float = -3.0) -> np.ndarray:
    x = x - x.mean()                                   # DC block
    peak = float(np.max(np.abs(x))) or 1.0
    return x / peak * (10 ** (dbfs / 20))


def write_wav(path: str, x: np.ndarray) -> None:
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def build() -> list[dict]:
    entries = []

    def add(cue: str, x: np.ndarray, loop: bool, role: str):
        x = normalise(x)
        write_wav(os.path.join(HERE, f"{cue}.wav"), x)
        entries.append({"id": cue, "path": f"{cue}.wav", "loop": loop, "seconds": round(len(x) / SR, 3), "role": role})

    # ── stems (music domain, long-loop) ──
    # dread: low minor drone with a slow beating fifth and a dark noise floor
    add("music_dread", drone(8.0, [55.0, 82.4, 110.0, 130.8], 0.004, 0.25) * 0.8
        + loop_noise(8.0, 180.0, 0.35), True, "stem")
    # calm: major-ish open voicing, higher, gentle, brighter noise air
    add("music_calm", drone(8.0, [130.8, 196.0, 261.6, 329.6, 392.0], 0.002, 0.125) * 0.7
        + loop_noise(8.0, 1200.0, 0.10), True, "stem")
    # triumph (optional): bright, fast shimmer, wide voicing
    add("music_triumph", drone(8.0, [196.0, 261.6, 329.6, 392.0, 523.3, 659.3], 0.006, 0.5) * 0.75
        + loop_noise(8.0, 2500.0, 0.15), True, "stem")

    # ── beds (ambient domain, long-loop) ──
    add("ambient_drone", drone(8.0, [36.7, 55.0, 73.4], 0.008, 0.125) * 0.9
        + loop_noise(8.0, 90.0, 0.5), True, "bed")
    add("ambient_white_noise", loop_noise(8.0, 6000.0, 1.0) * 0.6, True, "bed")
    # rain (optional): dense high-passed crackle over a hush
    nr = 8 * SR + SR
    rain = highpass(rng.standard_normal(nr), 1500.0) * (0.6 + 0.4 * (rng.random(nr) > 0.97))
    add("ambient_rain", make_loop(lowpass(rain, 7000.0, 1), 8 * SR) + loop_noise(8.0, 400.0, 0.3), True, "bed")

    # ── stings (music domain, oneshot overlays; shorter than any stem) ──
    add("music_victory_sting", sting(1.2, 330.0, 660.0, "bright"), False, "sting")   # rising
    add("music_defeat_sting", sting(1.4, 220.0, 82.0, "dark"), False, "sting")       # falling
    add("music_retreat_sting", sting(0.7, 440.0, 220.0, "dark"), False, "sting")     # short fall

    # ── ui / alerts (sfx domain, oneshot) ──
    tt = t(0.08)
    click = np.sin(2 * math.pi * 1800 * tt) * env(len(tt), 0.001, 0.06) + 0.4 * highpass(rng.standard_normal(len(tt)), 4000) * env(len(tt), 0.001, 0.03)
    add("ui_click", click, False, "ui")
    tt = t(0.25)
    add("ui_success", np.sin(2 * math.pi * 880 * tt) * env(len(tt), 0.005, 0.12) + np.sin(2 * math.pi * 1320 * tt) * env(len(tt), 0.08, 0.15), False, "ui")
    # warning: two short buzzes (square-ish) at a mid pitch
    tt = t(1.0)
    buzz = np.sign(np.sin(2 * math.pi * 330 * tt)) * 0.6 + np.sin(2 * math.pi * 330 * tt) * 0.4
    gate = ((tt % 0.5) < 0.22).astype(float)
    add("alert_warning", lowpass(buzz * gate, 2500.0, 1) * env(len(tt), 0.005, 0.05), False, "alert")
    # critical (optional): three fast buzzes, higher and harsher
    tt = t(1.2)
    buzz = np.sign(np.sin(2 * math.pi * 520 * tt)) * 0.7 + np.sin(2 * math.pi * 780 * tt) * 0.3
    gate = ((tt % 0.4) < 0.16).astype(float)
    add("alert_critical", lowpass(buzz * gate, 4000.0, 1) * env(len(tt), 0.005, 0.05), False, "alert")
    return entries


def main() -> None:
    entries = build()
    man = {
        "library": "felt-core",
        "version": "0.1.0",
        "cue_contract": "CORE_SOUND_PACK",
        "format": "wav_pcm16_mono",
        "sample_rate": SR,
        "generator": "synth_felt_pack.py (numpy, seed 71)",
        "grey_box": True,
        "entries": entries,
    }
    with open(os.path.join(HERE, "MANIFEST.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(man, fh, indent=2)
    for e in entries:
        print(f"  {e['id']:24s} {e['role']:6s} {'loop' if e['loop'] else 'once'} {e['seconds']:6.3f}s")
    print(f"MANIFEST.json: {len(entries)} entries")


if __name__ == "__main__":
    main()
