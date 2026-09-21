#!/usr/bin/env python3
"""diamond_clip.py — clip a ground render to the exact 2:1 diamond, AFTER colour has bled past it.

    python diamond_clip.py <in.png> <out.png> [--n N --m M] [--feather 1.0]

The camera script renders ground planes at 1.10× scale so packed-earth colour fills the frame
beyond the diamond. This step multiplies alpha by an analytic diamond (|x|/hw + |y|/hh <= 1),
anti-aliased by 4×4 supersampling, so edge pixels keep the render's colour (no black or white
fringe) and carry intermediate alpha (ANDON gate 8). It never resizes and never keys colour.
"""
from __future__ import annotations

import argparse

import numpy as np
from PIL import Image


def diamond_alpha(w: int, h: int, ss: int = 4, feather: float = 1.0) -> np.ndarray:
    hw, hh = w / 2.0, h / 2.0
    ys, xs = np.mgrid[0:h * ss, 0:w * ss]
    x = (xs + 0.5) / ss - hw
    y = (ys + 0.5) / ss - hh
    d = np.abs(x) / hw + np.abs(y) / hh      # 1.0 on the diamond edge
    # soft edge: full inside, linear falloff over `feather` px measured along x
    edge_px = feather / hw
    a = np.clip((1.0 - d) / edge_px + 1.0, 0.0, 1.0)
    a = a.reshape(h, ss, w, ss).mean(axis=(1, 3))
    return a


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--feather", type=float, default=1.0)
    args = ap.parse_args()
    im = Image.open(args.src).convert("RGBA")
    arr = np.asarray(im).astype(np.float32)
    w, h = im.size
    mask = diamond_alpha(w, h, feather=args.feather)
    arr[:, :, 3] = arr[:, :, 3] * mask
    out = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")
    out.save(args.dst, optimize=True)
    a = np.asarray(out)[:, :, 3]
    print(f"clipped {args.src} -> {args.dst}  {w}x{h}  opaque={float((a > 8).mean()):.3f}  "
          f"mid_alpha={int(((a > 0) & (a < 255)).sum())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
