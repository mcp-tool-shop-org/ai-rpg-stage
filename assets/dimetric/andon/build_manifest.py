#!/usr/bin/env python3
"""build_manifest.py — regenerate MANIFEST.json and every structure/prop sidecar from the ANDON logs.

    python andon/build_manifest.py            (run from assets/dimetric/)

The runtime consumes MANIFEST.json, so it is derived, never hand-edited: every entry's `andon` field
is read back from the ANDON log next to the file, `footprint`/`resolution`/`slab_row_px` from the
render.json + ANDON measurements, and a torch's `light_px` from its render.json. Files without a
passing ANDON log are listed with `andon: "fail"` (or "unchecked") so the client can refuse them.
"""
from __future__ import annotations

import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAMERA_EULER = [60, 0, 45]
TILE = [256, 128]
STRIP = 128


def load(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def andon_of(png):
    for cand in (os.path.splitext(png)[0] + ".andon.json", os.path.splitext(png)[0] + ".json",
                 os.path.join(os.path.dirname(png), "calibration_andon.json")):
        if os.path.isfile(cand):
            d = load(cand)
            if d.get("file", "").replace("\\", "/").endswith(os.path.basename(png)) or "calibration" in cand:
                return cand, d
    return None, None


def render_of(png):
    cand = os.path.splitext(png)[0] + ".render.json"
    return load(cand) if os.path.isfile(cand) else {}


def main():
    entries = []
    sun = None
    blender = engine = None

    def add(png, kind, phase, footprint=None, extra=None):
        nonlocal sun, blender, engine
        logp, log = andon_of(png)
        r = render_of(png)
        if r:
            sun = sun or r.get("sun_euler_deg")
            blender = blender or r.get("blender")
            engine = engine or r.get("engine")
        fp = footprint or (r.get("footprint") if r else None) or [1, 1]
        e = {"id": os.path.basename(os.path.dirname(png)) if os.path.basename(png) == "beauty.png"
             else os.path.splitext(os.path.basename(png))[0],
             "kind": kind, "path": rel(png), "footprint": fp,
             "andon": ("pass" if log and log.get("pass") else ("fail" if log else "unchecked")),
             "phase": phase, "andon_log": rel(logp) if logp else None}
        if log:
            e["resolution"] = log["measured"].get("size")
        if extra:
            e.update(extra)
        entries.append(e)
        return e, log, r

    # phase 0: calibration + rejected
    cal = os.path.join(ROOT, "camera", "calibration_square.png")
    if os.path.isfile(cal):
        add(cal, "ground", 0, [1, 1])
    for png in sorted(glob.glob(os.path.join(ROOT, "_rejected", "*.png"))):
        kind = "ground" if "ground" in png else ("prop" if "prop_" in png else "structure")
        add(png, kind, 0, [3, 3] if kind == "structure" else [1, 1])

    # ground tiles
    for png in sorted(glob.glob(os.path.join(ROOT, "ground", "*.png"))):
        add(png, "ground", 1, [1, 1])

    # structures: write sidecars
    for png in sorted(glob.glob(os.path.join(ROOT, "structures", "*", "beauty.png"))):
        sid = os.path.basename(os.path.dirname(png))
        phase = 1 if sid == "shed_2x2" else 2
        e, log, r = add(png, "structure", phase)
        if log and r:
            side = {"id": sid, "kind": "structure", "footprint": r["footprint"],
                    "resolution": log["measured"]["size"], "slab_width_px": log["measured"].get("slab_width_px"),
                    "slab_row_px": log["measured"].get("bottom_row"), "strip_px": STRIP, "azimuth_deg": 135,
                    "storeys": 2 if sid == "counting_house" else 1,
                    "andon": "pass" if log.get("pass") else "fail",
                    "person_px": 128, "facade_px": 384, "sun_euler_deg": r.get("sun_euler_deg"),
                    "camera_euler_deg": r.get("camera_euler_deg"),
                    "blend": rel(os.path.join(ROOT, "_src", sid, "blockout.blend")),
                    "world_to_screen": "world +X = screen down-right (cart x), world +Y = screen up-right; near vertex = (N,0,0)"}
            with open(os.path.join(os.path.dirname(png), "sidecar.json"), "w", encoding="utf-8", newline="\n") as fh:
                json.dump(side, fh, indent=2)
            e["sidecar"] = rel(os.path.join(os.path.dirname(png), "sidecar.json"))

    # props: sidecars with foot + optional light
    for png in sorted(glob.glob(os.path.join(ROOT, "props", "*", "beauty.png"))):
        pid = os.path.basename(os.path.dirname(png))
        e, log, r = add(png, "prop", 2, [1, 1])
        if log:
            w, h = log["measured"]["size"]
            side = {"id": pid, "kind": "prop", "footprint": [1, 1], "resolution": [w, h],
                    "foot_px": [w / 2.0, h - 1], "foot_is": "the cell's near (bottom) vertex",
                    "andon": "pass" if log.get("pass") else "fail", "sun_euler_deg": r.get("sun_euler_deg")}
            if r.get("light_px"):
                side["light_px"] = r["light_px"]
                e["light_px"] = r["light_px"]
            with open(os.path.join(os.path.dirname(png), "sidecar.json"), "w", encoding="utf-8", newline="\n") as fh:
                json.dump(side, fh, indent=2)
            e["sidecar"] = rel(os.path.join(os.path.dirname(png), "sidecar.json"))

    andon_version = None
    for e in entries:
        if e.get("andon_log"):
            andon_version = load(os.path.join(ROOT, e["andon_log"])).get("andon_version")
            if andon_version:
                break
    man = {"library": "dimetric-town", "version": "0.2.0", "tile": TILE, "strip_px": STRIP, "person_to_storey": 0.33,
           "camera": {"ortho": True, "euler_deg": CAMERA_EULER, "sensor_fit": "HORIZONTAL",
                      "ortho_scale_per_tile": 1.41421, "px_per_bu": 181.019},
           "azimuth_deg": 135, "sun_euler_deg": sun,
           "andon": {"script": "andon/iso_andon.py", "version": andon_version, "builder": "andon/build_manifest.py"},
           "renderer": {"blender": blender, "engine": engine, "camera_script": "camera/dimetric_60_45.py",
                        "ground_clip": "camera/diamond_clip.py", "sources": "_src/<id>/blockout.blend"},
           "godot_import": {"compress": "Lossless", "fix_alpha_border": True, "premult_alpha": False,
                            "vram_compressed": False, "mipmaps_ground": False,
                            "mipmaps_strips": "only if the camera zooms out"},
           "entries": entries}
    with open(os.path.join(ROOT, "MANIFEST.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(man, fh, indent=2)
    n_pass = sum(1 for e in entries if e["andon"] == "pass")
    print(f"MANIFEST.json: {len(entries)} entries, {n_pass} pass, "
          f"{sum(1 for e in entries if e['andon'] == 'fail')} fail, "
          f"{sum(1 for e in entries if e['andon'] == 'unchecked')} unchecked")
    for e in entries:
        print(f"  {e['andon']:9s} {e['kind']:9s} {e['id']:24s} {e['path']}")


if __name__ == "__main__":
    main()
