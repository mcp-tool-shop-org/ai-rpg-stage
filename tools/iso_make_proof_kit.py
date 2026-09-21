#!/usr/bin/env python3
"""Author the phase-1 dimetric proof kit: two dirt diamonds, one stone, one 2x2 grey-box shed.

Camera is implicit: 2:1 diamond geometry (edge arctan(0.5) = 26.565°), Film-Transparent
equivalent (RGBA, corners alpha 0). No diffusion. No loader resize.

    python tools/iso_make_proof_kit.py
"""
from __future__ import annotations

import json
import math
import os
import random
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "dimetric"
ANDON = ROOT / "tools" / "iso_andon.py"


def diamond_cover(w: int, h: int, x: float, y: float) -> float:
    """1 inside, 0 outside, 0-1 on a ~1.5px AA edge. Diamond points at mid-sides."""
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    hw, hh = w / 2.0, h / 2.0
    d = abs(x - cx) / hw + abs(y - cy) / hh
    edge = 1.5 / min(hw, hh)
    if d <= 1.0 - edge:
        return 1.0
    if d >= 1.0 + edge:
        return 0.0
    return max(0.0, min(1.0, 1.0 - (d - (1.0 - edge)) / (2.0 * edge)))


def shade(base: tuple[int, int, int], y: int, h: int, face: float) -> tuple[int, int, int]:
    t = 1.0 - 0.18 * abs(y - h / 2.0) / (h / 2.0)
    t *= face
    return tuple(max(0, min(255, int(c * t))) for c in base)


def paint_diamond(im: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int], face: float = 1.0, noise: float = 0.0, rng: random.Random | None = None) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    px = im.load()
    rng = rng or random.Random(1)
    for y in range(y0, y1):
        for x in range(x0, x1):
            cov = diamond_cover(w, h, x - x0, y - y0)
            if cov <= 0:
                continue
            r, g, b = shade(color, y - y0, h, face)
            if noise:
                k = 1.0 + noise * (rng.random() * 2 - 1)
                r, g, b = (max(0, min(255, int(v * k))) for v in (r, g, b))
            a = int(round(255 * cov))
            pr, pg, pb, pa = px[x, y]
            if a >= pa:
                # RGB stays dirt even as alpha fades (Fix Alpha Border / colour bleed).
                px[x, y] = (r, g, b, max(pa, a))


def make_ground(color: tuple[int, int, int], seed: int) -> Image.Image:
    im = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    paint_diamond(im, (0, 0, 256, 128), color, face=1.0, noise=0.08, rng=random.Random(seed))
    return im


def fill_quad(px, pts: list[tuple[float, float]], color: tuple[int, int, int], bounds: tuple[int, int]) -> None:
    """Scanline fill a convex quad."""
    w, h = bounds
    ys = [p[1] for p in pts]
    y0, y1 = int(math.floor(min(ys))), int(math.ceil(max(ys)))
    for y in range(max(0, y0), min(h, y1 + 1)):
        xs: list[float] = []
        for i, (x1, y1_) in enumerate(pts):
            x2, y2 = pts[(i + 1) % 4]
            if (y1_ <= y < y2) or (y2 <= y < y1_):
                t = (y - y1_) / (y2 - y1_ + 1e-9)
                xs.append(x1 + t * (x2 - x1))
        if len(xs) < 2:
            continue
        xa, xb = int(math.floor(min(xs))), int(math.ceil(max(xs)))
        for x in range(max(0, xa), min(w, xb + 1)):
            pr, pg, pb, pa = px[x, y]
            if pa < 250:
                px[x, y] = (*color, 255)


def make_shed() -> Image.Image:
    """2x2 grey-box shed. Slab 512 wide at 26.565°. Facade ~384 px (1:3 vs 128 px actor)."""
    w, h = 512, 640
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # Slab diamond sits on the bottom 256 rows.
    slab = (0, h - 256, w, h)
    paint_diamond(im, slab, (92, 78, 62), face=0.85, noise=0.04, rng=random.Random(7))

    # Wall / roof quads in image space (see spec: 60/45 dimetric box).
    left_pt = (0.0, h - 128.0)       # (0, 512)
    right_pt = (w - 1.0, h - 128.0)  # (511, 512)
    near_pt = (w / 2.0, h - 1.0)     # (256, 639)
    far_pt = (w / 2.0, float(h - 256))  # (256, 384)
    wall_h = 384.0
    roof_left = (left_pt[0], left_pt[1] - wall_h)    # (0, 128)
    roof_right = (right_pt[0], right_pt[1] - wall_h)  # (511, 128)
    roof_far = (far_pt[0], far_pt[1] - wall_h)        # (256, 0)
    roof_near = (near_pt[0], near_pt[1] - wall_h)     # (256, 255)

    px = im.load()
    fill_quad(px, [left_pt, far_pt, roof_far, roof_left], (110, 96, 78), (w, h))   # left wall, cooler
    fill_quad(px, [far_pt, right_pt, roof_right, roof_far], (148, 124, 96), (w, h))  # right wall, sun
    fill_quad(px, [roof_left, roof_far, roof_right, roof_near], (168, 140, 108), (w, h))  # roof

    # Door hole on the near-right face — punch alpha so it reads as a shed, not a crate.
    draw = ImageDraw.Draw(im)
    door = [
        (w / 2.0 + 20, h - 90),
        (w / 2.0 + 90, h - 128),
        (w / 2.0 + 90, h - 128 - 160),
        (w / 2.0 + 20, h - 90 - 160),
    ]
    draw.polygon(door, fill=(40, 32, 28, 255))
    return im


def make_crate() -> Image.Image:
    """1x1 grey-box crate. 256x256, slab 256 wide."""
    w, h = 256, 256
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    paint_diamond(im, (0, h - 128, w, h), (86, 74, 58), face=0.9, noise=0.03, rng=random.Random(3))
    left_pt = (0.0, h - 64.0)
    right_pt = (w - 1.0, h - 64.0)
    far_pt = (w / 2.0, float(h - 128))
    near_pt = (w / 2.0, float(h - 1))
    wall_h = 96.0
    px = im.load()
    fill_quad(px, [left_pt, far_pt, (far_pt[0], far_pt[1] - wall_h), (left_pt[0], left_pt[1] - wall_h)], (100, 88, 70), (w, h))
    fill_quad(px, [far_pt, right_pt, (right_pt[0], right_pt[1] - wall_h), (far_pt[0], far_pt[1] - wall_h)], (130, 108, 82), (w, h))
    fill_quad(
        px,
        [
            (left_pt[0], left_pt[1] - wall_h),
            (far_pt[0], far_pt[1] - wall_h),
            (right_pt[0], right_pt[1] - wall_h),
            (near_pt[0], near_pt[1] - wall_h),
        ],
        (150, 126, 96),
        (w, h),
    )
    return im


def andon(path: Path, kind: str, fp: str) -> bool:
    r = subprocess.run(
        [sys.executable, str(ANDON), str(path), "--kind", kind, "--footprint", fp],
        cwd=str(ROOT),
    )
    return r.returncode == 0


def write_png(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "_rejected").mkdir(exist_ok=True)

    dirt_a = make_ground((118, 96, 70), 11)
    dirt_b = make_ground((108, 90, 64), 23)
    stone = make_ground((86, 88, 90), 31)
    shed = make_shed()
    crate = make_crate()

    files = [
        (dirt_a, OUT / "ground" / "dirt_a.png", "ground", "1,1"),
        (dirt_b, OUT / "ground" / "dirt_b.png", "ground", "1,1"),
        (stone, OUT / "ground" / "stone_a.png", "ground", "1,1"),
        (shed, OUT / "structures" / "shed_2x2" / "beauty.png", "structure", "2,2"),
        (crate, OUT / "props" / "crate_1x1" / "beauty.png", "prop", "1,1"),
    ]
    failed = 0
    entries = []
    for im, path, kind, fp in files:
        write_png(im, path)
        ok = andon(path, kind, fp)
        print(("PASS" if ok else "FAIL"), path.relative_to(ROOT))
        if not ok:
            failed += 1
        n, m = (int(x) for x in fp.split(","))
        entries.append({
            "id": path.parent.name if kind != "ground" else path.stem,
            "kind": kind,
            "path": str(path.relative_to(ROOT / "assets" / "dimetric")).replace("\\", "/"),
            "footprint": [n, m],
            "andon": "pass" if ok else "fail",
            "phase": 1,
        })

    sidecar = {
        "id": "shed_2x2",
        "kind": "structure",
        "footprint": [2, 2],
        "resolution": [512, 640],
        "slab_width_px": 512,
        "slab_row_px": 639,
        "strip_px": 128,
        "azimuth_deg": 135,
        "storeys": 1,
        "andon": "pass" if failed == 0 else "fail",
    }
    (OUT / "structures" / "shed_2x2" / "sidecar.json").write_text(
        json.dumps(sidecar, indent=2) + "\n", encoding="utf-8"
    )
    manifest = {
        "library": "dimetric-town",
        "version": "0.1.0",
        "tile": [256, 128],
        "strip_px": 128,
        "person_to_storey": 0.33,
        "camera": {"ortho": True, "euler_deg": [60, 0, 45], "sensor_fit": "HORIZONTAL", "note": "geometry baked as 2:1 diamond; Blender script not required for phase 1"},
        "azimuth_deg": 135,
        "entries": entries,
    }
    (OUT / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    # Point the dead folder at the new library without deleting evidence if it is still there.
    iso_dir = ROOT / "assets" / "iso"
    if iso_dir.is_dir():
        readme = iso_dir / "README.md"
        readme.write_text(
            "Dead. These plates failed the dimetric ANDON (wrong camera and/or no alpha).\n"
            "Legal art lives in `res://assets/dimetric/`.\n",
            encoding="utf-8",
        )
    return 1 if failed else 0


if __name__ == "__main__":
    os.chdir(ROOT)
    sys.exit(main())
