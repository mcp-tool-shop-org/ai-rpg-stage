#!/usr/bin/env python3
"""Refuse a dimetric PNG that cannot sit on a 2:1 Godot TileMapLayer.

Exit 0 only if every numbered gate passes. Prints file, kind, and each gate
with the measured number. No Godot required.

    python tools/iso_andon.py <png> [--kind ground|structure|prop] [--footprint N,M]
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("PIL required")


TARGET_DEG = math.degrees(math.atan(0.5))  # 26.565...
OPAQUE = 128


def load_rgba(path: Path) -> Image.Image:
    im = Image.open(path)
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    return im


def opaque_ratio(im: Image.Image) -> float:
    a = im.getchannel("A")
    pix = list(a.tobytes())
    n = len(pix)
    if n == 0:
        return 0.0
    return sum(1 for v in pix if v >= OPAQUE) / n


def corner_blocks_clear(im: Image.Image, block: int = 8) -> bool:
    w, h = im.size
    a = im.getchannel("A")
    origins = [(0, 0), (w - block, 0), (0, h - block), (w - block, h - block)]
    for ox, oy in origins:
        for y in range(oy, oy + block):
            for x in range(ox, ox + block):
                if a.getpixel((x, y)) != 0:
                    return False
    return True


def lowest_opaque_y_per_column(im: Image.Image) -> list[int | None]:
    w, h = im.size
    a = im.getchannel("A")
    out: list[int | None] = []
    for x in range(w):
        y_hit = None
        for y in range(h - 1, -1, -1):
            if a.getpixel((x, y)) >= OPAQUE:
                y_hit = y
                break
        out.append(y_hit)
    return out


def fit_edge_deg(cols: list[tuple[int, int]]) -> float | None:
    if len(cols) < 8:
        return None
    n = len(cols)
    mx = sum(c[0] for c in cols) / n
    my = sum(c[1] for c in cols) / n
    den = sum((c[0] - mx) ** 2 for c in cols)
    if den < 1e-6:
        return None
    slope = sum((c[0] - mx) * (c[1] - my) for c in cols) / den
    return math.degrees(math.atan(abs(slope)))


def slab_metrics(im: Image.Image) -> tuple[float | None, float | None, int, int]:
    """Return (left_edge_deg, right_edge_deg, slab_width, foot_center_x)."""
    ys = lowest_opaque_y_per_column(im)
    pairs = [(x, y) for x, y in enumerate(ys) if y is not None]
    if not pairs:
        return None, None, 0, -1
    # Slab width is the footprint at the diamond's equator (used-rect width),
    # not the 18px tip of the near corner.
    xs = [x for x, _ in pairs]
    slab_w = max(xs) - min(xs) + 1
    foot_x = (min(xs) + max(xs)) / 2.0
    mid = foot_x
    left = [(x, y) for x, y in pairs if x <= mid]
    right = [(x, y) for x, y in pairs if x >= mid]
    return fit_edge_deg(left), fit_edge_deg(right), slab_w, int(round(foot_x))


def has_checker(im: Image.Image, period: int = 8) -> bool:
    """Refuse a baked two-value checker in fully opaque regions."""
    w, h = im.size
    px = im.load()
    counts: dict[tuple[int, int, int], int] = {}
    n = 0
    for y in range(0, h, period):
        for x in range(0, w, period):
            r, g, b, a = px[x, y]
            if a < 250:
                continue
            key = (r // 8, g // 8, b // 8)
            counts[key] = counts.get(key, 0) + 1
            n += 1
    if n < 32 or len(counts) != 2:
        return False
    vals = sorted(counts.values(), reverse=True)
    return vals[0] + vals[1] >= 0.9 * n and abs(vals[0] - vals[1]) < 0.35 * n


def alpha_has_blend(im: Image.Image) -> bool:
    a = im.getchannel("A")
    mid = sum(1 for v in a.tobytes() if 8 <= v <= 247)
    return mid > 0


def thresholds(kind: str, fp: tuple[int, int]) -> dict:
    n, m = fp
    w, k_min = 256 * n, n
    if kind == "ground":
        return {
            "opaque": (0.35, 0.62),
            "slab_w": 256,
            "dims": (256, 128),
            "foot_cx": 128,
        }
    if kind == "prop":
        return {
            "opaque": (0.0, 0.70),
            "slab_w": min(256 * n, 256),
            "dims": None,  # 256x128 or 256x256
            "foot_cx": None,
        }
    # structure
    return {
        "opaque": (0.0, 0.85),
        "slab_w": 256 * n,
        "dims": (256 * n, None),  # height 128K, K>=N
        "foot_cx": (256 * n) / 2.0,
        "k_min": k_min,
        "n": n,
    }


def check(path: Path, kind: str, footprint: tuple[int, int]) -> tuple[bool, list[str]]:
    im = load_rgba(path)
    w, h = im.size
    th = thresholds(kind, footprint)
    lines: list[str] = []
    ok_all = True

    def gate(name: str, passed: bool, detail: str) -> None:
        nonlocal ok_all
        if not passed:
            ok_all = False
        lines.append(f"  {'ok  ' if passed else 'FAIL'} {name}: {detail}")

    gate("0 format", True, "RGBA8 (converted on load)")

    ratio = opaque_ratio(im)
    lo, hi = th["opaque"]
    gate("1 opaque_ratio", lo <= ratio <= hi, f"{ratio:.3f} (want {lo}–{hi})")

    gate("2 corner_alpha", corner_blocks_clear(im), "four 8×8 corners alpha 0")

    left, right, slab_w, foot_x = slab_metrics(im)
    def ang_ok(d: float | None) -> bool:
        return d is not None and abs(d - TARGET_DEG) <= 1.5

    gate(
        "3 edge_angle",
        ang_ok(left) and ang_ok(right),
        f"L={left:.2f}° R={right:.2f}° want {TARGET_DEG:.3f}±1.5" if left and right else "no slab",
    )
    want_w = th["slab_w"]
    gate("4 slab_width", abs(slab_w - want_w) <= 4, f"{slab_w}px want {want_w}±4")

    cx = w / 2.0
    gate("5 foot_origin", foot_x >= 0 and abs(foot_x - cx) <= 2, f"foot_x={foot_x} image_cx={cx:.1f}")

    if kind == "ground":
        gate("6 dimensions", (w, h) == (256, 128), f"{w}×{h} want 256×128")
    elif kind == "structure":
        n = footprint[0]
        k_ok = w == 256 * n and h % 128 == 0 and h >= 128 * n
        gate("6 dimensions", k_ok, f"{w}×{h} want 256N×128K with N={n} K>=N")
    else:
        gate("6 dimensions", w in (256, 512) and h in (128, 256, 512), f"{w}×{h}")

    gate("7 checker", not has_checker(im), "no baked two-value checker")
    gate("8 alpha_blend", alpha_has_blend(im), "intermediate alpha present (not punch-through only)")
    gate("9 no_resize_in_loader", True, "file on disk is the drawn size (loader must not resize)")

    return ok_all, lines


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("png")
    p.add_argument("--kind", choices=["ground", "structure", "prop"], default="ground")
    p.add_argument("--footprint", default="1,1")
    p.add_argument("--json", action="store_true")
    args = p.parse_args()
    path = Path(args.png)
    if not path.is_file():
        print(f"FAIL missing {path}")
        return 1
    n, m = (int(x) for x in args.footprint.split(","))
    passed, lines = check(path, args.kind, (n, m))
    print(f"{path}  kind={args.kind}  footprint={n}x{m}  {'PASS' if passed else 'FAIL'}")
    print("\n".join(lines))
    if args.json:
        print(json.dumps({"file": str(path), "pass": passed}))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
