#!/usr/bin/env python3
"""iso_andon.py — the gate a 2:1 dimetric plate must pass BEFORE it enters res://.

Implements every numbered check of the Dimetric Town Asset Library spec, section 3
(the readouts KB `dimetric-knowledge`, specs/dimetric-asset-library.md). Exit 0 only when
every gate passes; exit 1 on any FAIL; exit 2 if the file cannot be decoded. No Godot needed.

    python iso_andon.py <png> [--kind ground|structure|prop] [--footprint N,M] [--json <log>]

Gate 0   decoded format is RGBA8 (an RGB8 plate killed the ground atlas blit).
Gate 1   opaque ratio      ground 0.35–0.62 · structure < 0.85 · prop < 0.70
Gate 2   four 8×8 corner blocks are alpha 0
Gate 3   lowest-opaque-row slab edges are 26.565° ± 1.5° (least-squares fit of the
         silhouette's lower-left and lower-right edges, from the near vertex up)
Gate 4   slab width       ground 256 ± 4 · structure 128·(N+M) ± 4 (= 256·N when square) · prop ≤ 256 ± 4
Gate 5   foot origin      used-rect centre X = image centre X ± 2 px
Gate 6   dimensions       ground 256×128 · structure 128·(N+M) × 128·K, K ≥ max(N,M) · prop 256×128 or 256×256
Gate 7   no checkerboard baked into RGB: per-64px-tile, phase-searched correlation with an 8/12/16 px
         two-value checker on high-passed luminance; fail at ≥ 0.35 (measured: baked plates 0.80 / 0.41, clean ≤ 0.27)
Gate 8   alpha histogram has intermediate values (a painterly edge), not ALPHA_BIT only
Gate 9   no loader resize: the file on disk is the size Godot draws (no size_limit in a
         sibling .import; dimensions already exact per gate 6)

ANDON_VERSION below is written into every log so a plate can be re-gated when a rule moves.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

ANDON_VERSION = "0.1.1"
TILE_W, TILE_H = 256, 128
EDGE_DEG = math.degrees(math.atan(0.5))  # 26.565°
EDGE_TOL = 1.5
OPAQUE_T = 8       # alpha > 8 counts as opaque for the ratio
EDGE_T = 128       # alpha >= 128 defines the silhouette used for geometry


def _kind_from_name(path: str) -> str:
    n = os.path.basename(path).lower()
    if n.startswith(("ground", "dirt", "stone", "calibration")):
        return "ground"
    if n.startswith("prop"):
        return "prop"
    return "structure"


def _fit_angle(points: list[tuple[float, float]]) -> float | None:
    """Angle (deg from horizontal) of the least-squares line through (x, y) points."""
    if len(points) < 6:
        return None
    xs = np.array([p[0] for p in points], dtype=float)
    ys = np.array([p[1] for p in points], dtype=float)
    # fit x as a function of y (rows are the independent variable; edges are steep in x)
    A = np.vstack([ys, np.ones_like(ys)]).T
    slope, _ = np.linalg.lstsq(A, xs, rcond=None)[0]   # dx/dy
    if abs(slope) < 1e-6:
        return 90.0
    return math.degrees(math.atan(1.0 / abs(slope)))


def _box_blur(x: np.ndarray, size: int) -> np.ndarray:
    """Mean filter with a cumulative-sum box, edge-padded (no scipy dependency)."""
    pad = size // 2
    xp = np.pad(x, pad, mode="edge")
    cs = np.cumsum(np.cumsum(xp, axis=0), axis=1)
    cs = np.pad(cs, ((1, 0), (1, 0)))
    h, w = x.shape
    tot = (cs[size:size + h, size:size + w] - cs[:h, size:size + w]
           - cs[size:size + h, :w] + cs[:h, :w])
    return tot / float(size * size)


def _checker_score(rgb: np.ndarray, alpha: np.ndarray, cell: int, tile: int = 64) -> float:
    """Max normalised correlation, over 64 px tiles and all cell phases, between the high-passed
    luminance and a two-value checkerboard of `cell` px. A baked checker is faint (one luminance
    step) and lives in the flat background, so the search runs per tile and skips tiles that are
    either flat (nothing to detect) or textured content (std > 12, where any checker is art)."""
    lum = rgb.astype(float).mean(axis=2)
    hp = lum - _box_blur(lum, 2 * cell)
    h, w = lum.shape
    if h < tile or w < tile:
        return 0.0
    yy, xx = np.mgrid[0:tile, 0:tile]
    step = max(1, cell // 3)
    pats = []
    for py in range(0, 2 * cell, step):
        for px in range(0, 2 * cell, step):
            p = np.where((((yy + py) // cell) + ((xx + px) // cell)) % 2 == 0, 1.0, -1.0)
            pats.append((p - p.mean()) / (p.std() + 1e-9))
    best = 0.0
    for y0 in range(0, h - tile + 1, tile):
        for x0 in range(0, w - tile + 1, tile):
            t = hp[y0:y0 + tile, x0:x0 + tile]
            sd = t.std()
            if sd < 0.15 or sd > 12.0:
                continue
            tn = (t - t.mean()) / sd
            r = max(abs((tn * p).mean()) for p in pats)
            if r > best:
                best = r
    return float(best)


def gate(path: str, kind: str, footprint: tuple[int, int] | None, slab: bool = False) -> dict:
    out = {"andon_version": ANDON_VERSION, "file": path, "kind": kind, "gates": {}, "measured": {}}
    g = out["gates"]
    meas = out["measured"]

    def rec(num: int, ok: bool, detail: str) -> None:
        g[str(num)] = {"ok": bool(ok), "detail": detail}

    try:
        im = Image.open(path)
        mode = im.mode
        im.load()
    except Exception as e:  # noqa: BLE001
        out["decode_error"] = str(e)
        return out
    meas["mode"] = mode
    w, h = im.size
    meas["size"] = [w, h]

    # Gate 0 — format
    rec(0, mode == "RGBA", f"decoded mode {mode} (need RGBA)")
    arr = np.asarray(im.convert("RGBA"))
    a = arr[:, :, 3]
    rgb = arr[:, :, :3]
    opaque = a > OPAQUE_T
    edge = a >= EDGE_T

    n_m = footprint or (1, 1)
    N, M = n_m

    # Gate 1 — opaque ratio
    ratio = float(opaque.mean())
    meas["opaque_ratio"] = round(ratio, 4)
    lim = {"ground": (0.35, 0.62), "structure": (0.0, 0.85), "prop": (0.0, 0.70)}[kind]
    ok1 = lim[0] <= ratio <= lim[1] if kind == "ground" else ratio < lim[1]
    rec(1, ok1, f"opaque ratio {ratio:.3f} (allowed {lim[0]:.2f}–{lim[1]:.2f})")

    # Gate 2 — corners
    corners = {
        "tl": a[:8, :8], "tr": a[:8, -8:], "bl": a[-8:, :8], "br": a[-8:, -8:]}
    cmax = {k: int(v.max()) for k, v in corners.items()}
    meas["corner_alpha_max"] = cmax
    rec(2, all(v == 0 for v in cmax.values()), f"corner 8×8 alpha max {cmax} (need all 0)")

    # Silhouette rows
    rows_any = np.where(edge.any(axis=1))[0]
    if rows_any.size == 0:
        rec(3, False, "no silhouette (no pixel with alpha ≥ 128)")
        rec(4, False, "no silhouette")
        rec(5, False, "no silhouette")
    else:
        bottom = int(rows_any.max())
        top = int(rows_any.min())
        xmin = np.full(h, -1)
        xmax = np.full(h, -1)
        for r in range(top, bottom + 1):
            xs = np.where(edge[r])[0]
            if xs.size:
                xmin[r], xmax[r] = int(xs.min()), int(xs.max())
        bx = np.where(edge[bottom])[0]
        vertex_x = float(bx.mean())
        meas["bottom_row"] = bottom
        meas["bottom_vertex_x"] = round(vertex_x, 1)

        # Gate 3 — slab edge angles. Fit from 3 rows above the vertex to 3 rows below the corner.
        left_rows = range(bottom - 3, max(top, bottom - 64 * N + 3), -1)
        right_rows = range(bottom - 3, max(top, bottom - 64 * M + 3), -1)
        lpts = [(float(xmin[r]), float(r)) for r in left_rows if xmin[r] >= 0]
        rpts = [(float(xmax[r]), float(r)) for r in right_rows if xmax[r] >= 0]
        la, ra = _fit_angle(lpts), _fit_angle(rpts)
        meas["edge_left_deg"] = None if la is None else round(la, 2)
        meas["edge_right_deg"] = None if ra is None else round(ra, 2)
        ok3 = (la is not None and ra is not None
               and abs(la - EDGE_DEG) <= EDGE_TOL and abs(ra - EDGE_DEG) <= EDGE_TOL)
        if kind == "prop" and not slab:
            # spec §3 gate 3: "same if a slab exists". A barrel or bollard has no diamond slab; its
            # lowest rows are a curve. Measured and logged, gated only when --slab asserts a slab.
            rec(3, True, f"no slab asserted for this prop; measured edges L {la} R {ra} (informational)")
        else:
            rec(3, ok3, f"slab edges L {la if la is None else round(la, 2)}° R {ra if ra is None else round(ra, 2)}° "
                        f"(need {EDGE_DEG:.3f} ± {EDGE_TOL})")

        # Gate 4 — slab width: widest row inside the slab window (from vertex up to the far corner + 4)
        lo = max(top, bottom - 64 * max(N, M) - 4)
        widths = [(xmax[r] - xmin[r] + 1) for r in range(lo, bottom + 1) if xmin[r] >= 0]
        slab_w = int(max(widths)) if widths else 0
        meas["slab_width_px"] = slab_w
        exp_w = 128 * (N + M) if kind == "structure" else TILE_W
        if kind == "prop":
            ok4 = slab_w <= TILE_W + 4
            rec(4, ok4, f"slab width {slab_w} px (need ≤ {TILE_W} ± 4)")
        else:
            ok4 = abs(slab_w - exp_w) <= 4
            rec(4, ok4, f"slab width {slab_w} px (need {exp_w} ± 4)")

        # Gate 5 — foot origin
        cols_any = np.where((a > 0).any(axis=0))[0]
        used_cx = (cols_any.min() + cols_any.max()) / 2.0
        img_cx = (w - 1) / 2.0
        meas["used_rect"] = [int(cols_any.min()), int(np.where((a > 0).any(axis=1))[0].min()),
                             int(cols_any.max()), int(np.where((a > 0).any(axis=1))[0].max())]
        meas["used_centre_x"] = round(float(used_cx), 1)
        d5 = abs(used_cx - img_cx)
        rec(5, d5 <= 2.0, f"used-rect centre X {used_cx:.1f} vs image centre {img_cx:.1f} (Δ {d5:.1f}, need ≤ 2); "
                          f"bottom vertex X {vertex_x:.1f}")

    # Gate 6 — dimensions
    if kind == "ground":
        ok6 = (w, h) == (TILE_W, TILE_H)
        need = f"{TILE_W}×{TILE_H}"
    elif kind == "structure":
        exp_w = 128 * (N + M)
        ok6 = (w == exp_w) and (h % TILE_H == 0) and (h // TILE_H >= max(N, M))
        need = f"{exp_w}×128·K with K ≥ {max(N, M)}"
    else:
        ok6 = (w, h) in ((TILE_W, TILE_H), (TILE_W, TILE_W))
        need = "256×128 or 256×256"
    rec(6, ok6, f"{w}×{h} (need {need})")

    # Gate 7 — checker baked into RGB (8 / 12 / 16 px cells), searched per 64 px tile
    scores = {f"cell_{c}": round(_checker_score(rgb, a, c), 3) for c in (8, 12, 16)}
    meas["checker_scores"] = scores
    worst = max(scores.values()) if scores else 0.0
    rec(7, worst < 0.35, f"checker correlation max {worst:.2f} (fail ≥ 0.35; measured plates: baked 0.80 / 0.41, clean ≤ 0.27) {scores}")

    # Gate 8 — intermediate alpha exists
    mid = int(((a > 0) & (a < 255)).sum())
    meas["intermediate_alpha_px"] = mid
    rec(8, mid >= 48, f"{mid} px with 0 < alpha < 255 (need ≥ 48)")

    # Gate 9 — no loader resize
    imp = path + ".import"
    resize_note = "no .import sidecar; dimensions gated by 6"
    ok9 = True
    if os.path.isfile(imp):
        txt = open(imp, encoding="utf-8", errors="replace").read()
        if "process/size_limit=" in txt:
            val = txt.split("process/size_limit=")[1].split()[0]
            ok9 = val.strip() == "0"
            resize_note = f".import size_limit={val}"
    rec(9, ok9 and ok6, resize_note + ("" if ok6 else "; dimensions wrong so Godot would draw the wrong size"))

    out["pass"] = all(v["ok"] for v in g.values())
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("png")
    ap.add_argument("--kind", choices=["ground", "structure", "prop"])
    ap.add_argument("--footprint", help="N,M tiles for a structure (default 1,1)")
    ap.add_argument("--json", help="write the log here (default: <png>.andon.json next to the file)")
    ap.add_argument("--slab", action="store_true", help="prop stands on a diamond slab: enforce gate 3")
    args = ap.parse_args()

    kind = args.kind or _kind_from_name(args.png)
    fp = None
    if args.footprint:
        n, m = [int(x) for x in args.footprint.split(",")]
        fp = (n, m)
    res = gate(args.png, kind, fp, slab=args.slab)
    log = args.json or (os.path.splitext(args.png)[0] + ".andon.json")
    with open(log, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(res, fh, indent=2)

    print(f"file   {args.png}")
    print(f"kind   {kind}" + (f"  footprint {fp[0]}x{fp[1]}" if fp else ""))
    if "decode_error" in res:
        print(f"DECODE FAIL  {res['decode_error']}")
        return 2
    for num, gv in res["gates"].items():
        print(f"gate {num}  {'ok  ' if gv['ok'] else 'FAIL'}  {gv['detail']}")
    print(f"result {'PASS' if res['pass'] else 'FAIL'}   log {log}")
    return 0 if res["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
