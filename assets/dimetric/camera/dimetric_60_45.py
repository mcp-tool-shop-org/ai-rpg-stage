# dimetric_60_45.py — the 2:1 dimetric camera as a Blender setting, headless.
#
#   blender --background --python dimetric_60_45.py -- --n 1 --out <dir>
#   blender --background --python dimetric_60_45.py -- --scene shed --n 2 --m 2 --name shed_2x2 --out <dir> --save blockout.blend
#
# Contract (spec §2): orthographic camera, rotation_euler (60°, 0, 45°), sensor_fit HORIZONTAL,
# ortho_scale = (N+M)/√2 (= 1.41421·N for a square footprint), resolution 128·(N+M) × 128·K,
# Film Transparent, PNG RGBA, alpha from the Combined pass. One Sun, one azimuth. True isometry
# (X = 54.736°) is forbidden. One Blender unit = one tile on the XY plane.
#
# Scenes:
#   calibration  a flat N×M plane, exactly the diamond (the spec's calibration square at N=1)
#   ground       a flat plane scaled 1.10 so colour bleeds past the diamond; clip it afterwards with
#                diamond_clip.py (this file never keys or crops)
#   shed         a grey-box one-storey shed on an N×M footprint, 1:3 person:facade, gable roof,
#                a hidden 1 BU cube and a hidden 0.816 BU "person" for scale in the .blend
#
# Screen mapping produced by this rig (verified by the calibration render):
#   world +X → screen down-right (cart x of iso_math), world +Y → screen up-right,
#   near (bottom) vertex of the footprint = (N, 0, 0), left = (0, 0), right = (N, M), top = (0, M).
import argparse
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Matrix, Vector

PX_PER_TILE_W = 256
PX_PER_TILE_H = 128
STRIP_PX = 128
ACTOR_PX = 128                       # the identity unit: one actor = 128 px on screen
PX_PER_BU = PX_PER_TILE_W / math.sqrt(2.0)          # 181.02 px per Blender unit (isotropic ortho)
SCREEN_UP_PER_Z = math.cos(math.radians(30.0))      # a vertical BU projects to 0.866 BU of screen-up
ACTOR_BU = ACTOR_PX / (PX_PER_BU * SCREEN_UP_PER_Z)  # 0.816 BU tall person
PERSON_TO_STOREY = 3.0
CAM_EULER_DEG = (60.0, 0.0, 45.0)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", choices=["calibration", "ground", "shed", "house", "stair", "prop"], default="calibration")
    ap.add_argument("--storeys", type=int, default=1)
    ap.add_argument("--roof", choices=["gable", "flat"], default="gable")
    ap.add_argument("--wall-scale", type=float, default=1.0, help="stretch the per-storey wall height (warehouse 1.3)")
    ap.add_argument("--prop", choices=["well", "cart", "barrel", "crate", "torch", "bollard"], default="barrel")
    ap.add_argument("--n", type=int, default=1, help="footprint tiles along world X")
    ap.add_argument("--m", type=int, default=None, help="footprint tiles along world Y (default = n)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default=None)
    ap.add_argument("--variant", default="a", help="ground look: a | b | stone")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--save", default=None, help="save the .blend here after rendering")
    return ap.parse_args(argv)


def fresh_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    ver = bpy.app.version
    # 4.2–4.x call it BLENDER_EEVEE_NEXT; 5.x renamed it back to BLENDER_EEVEE.
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = scene.render.pixel_aspect_y = 1.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 15
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 64
        if hasattr(scene.eevee, "use_shadows"):
            scene.eevee.use_shadows = True
    # world: neutral grey fill so shadowed faces are readable, not black
    world = bpy.data.worlds.new("DimetricWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.42, 0.42, 0.42, 1.0)
        bg.inputs[1].default_value = 1.0
    scene.world = world
    return scene, ver


def add_camera(scene, n, m, res_x, res_y):
    cam_data = bpy.data.cameras.new("DimetricCam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = (n + m) / math.sqrt(2.0)
    cam_data.clip_start = 0.01
    cam_data.clip_end = 200.0
    cam = bpy.data.objects.new("DimetricCam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((n / 2.0, m / 2.0, 0.0))
    rot = Euler(tuple(math.radians(d) for d in CAM_EULER_DEG), "XYZ")
    cam.matrix_world = Matrix.Translation(target) @ rot.to_matrix().to_4x4() @ Matrix.Translation((0.0, 0.0, 40.0))
    cam.rotation_euler = rot
    scene.camera = cam
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    return cam


def add_sun(scene):
    """One Sun from screen top-left so the shadow falls toward the diamond's bottom-right."""
    light = bpy.data.lights.new("Sun", "SUN")
    light.energy = 2.6
    light.angle = math.radians(2.0)
    sun = bpy.data.objects.new("Sun", light)
    scene.collection.objects.link(sun)
    rot = Euler(tuple(math.radians(d) for d in CAM_EULER_DEG), "XYZ").to_matrix()
    screen_right = rot @ Vector((1.0, 0.0, 0.0))
    screen_up = rot @ Vector((0.0, 1.0, 0.0))
    # Key from screen-LEFT with a little top: a pure top-left key grazes both visible walls (they face
    # down-left and down-right), so the building reads as a dark block under a bright roof. Weighting
    # screen-left 1.0 : screen-up 0.35 lights the down-left wall (dot ≈ 0.55), leaves the down-right
    # wall to ambient, and throws the shadow toward the diamond's bottom-right. One lamp for every plate.
    from_dir = (-screen_right * 1.0 + screen_up * 0.35).normalized()
    to_scene = -from_dir
    sun.rotation_euler = to_scene.to_track_quat("-Z", "Y").to_euler()
    sun.location = from_dir * 30.0
    return sun, tuple(round(math.degrees(v), 3) for v in sun.rotation_euler)


def flat_material(name, rgb, rough=0.85):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return mat


def ground_material(variant, seed):
    mat = bpy.data.materials.new(f"Ground_{variant}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.95
    tex = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "4D"
    noise.inputs["W"].default_value = float(seed) * 3.7 + (1.0 if variant == "b" else 0.0)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.noise_dimensions = "4D"
    grain.inputs["W"].default_value = float(seed) * 1.3 + 7.0
    grain.inputs["Scale"].default_value = 28.0
    grain.inputs["Detail"].default_value = 4.0
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 0.35   # Factor_Float; colour sockets are inputs 6/7, colour result is outputs[2]
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    if variant == "stone":
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 5.5
        vor.inputs["Randomness"].default_value = 0.6
        vramp = nt.nodes.new("ShaderNodeValToRGB")
        vramp.color_ramp.elements[0].position = 0.0
        vramp.color_ramp.elements[0].color = (0.16, 0.17, 0.18, 1)   # grout
        vramp.color_ramp.elements[1].position = 0.08
        vramp.color_ramp.elements[1].color = (0.46, 0.47, 0.48, 1)   # stone face
        noise.inputs["Scale"].default_value = 9.0
        ramp.color_ramp.elements[0].color = (0.40, 0.41, 0.42, 1)
        ramp.color_ramp.elements[1].color = (0.56, 0.55, 0.53, 1)
        mix2 = nt.nodes.new("ShaderNodeMix")
        mix2.data_type = "RGBA"
        mix2.blend_type = "MULTIPLY"
        mix2.inputs[0].default_value = 1.0
        nt.links.new(tex.outputs["Object"], vor.inputs["Vector"])
        nt.links.new(vor.outputs["Distance"], vramp.inputs["Fac"])
        nt.links.new(tex.outputs["Object"], noise.inputs["Vector"])
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mix2.inputs[6])
        nt.links.new(vramp.outputs["Color"], mix2.inputs[7])
        nt.links.new(mix2.outputs[2], mix.inputs[6])
        nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    else:
        noise.inputs["Scale"].default_value = 3.0
        noise.inputs["Detail"].default_value = 6.0
        noise.inputs["Roughness"].default_value = 0.6
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[0].color = (0.30, 0.22, 0.15, 1)    # packed earth, dark
        ramp.color_ramp.elements[1].position = 0.70
        ramp.color_ramp.elements[1].color = (0.52, 0.41, 0.29, 1)    # packed earth, light
        nt.links.new(tex.outputs["Object"], noise.inputs["Vector"])
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mix.inputs[6])
        nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(tex.outputs["Object"], grain.inputs["Vector"])
    nt.links.new(grain.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def add_plane(scene, n, m, scale, mat):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(n / 2.0, m / 2.0, 0.0))
    plane = bpy.context.active_object
    plane.name = "Ground"
    plane.scale = (n * scale, m * scale, 1.0)
    plane.data.materials.append(mat)
    return plane


def add_box(name, x0, y0, z0, dx, dy, dz, mat, scene):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x0 + dx / 2.0, y0 + dy / 2.0, z0 + dz / 2.0))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (dx, dy, dz)
    ob.data.materials.append(mat)
    return ob


def build_house(scene, n, m, storeys=1, roof="gable", wall_scale=1.0):
    """Grey-box house: full-footprint walls (slab width = 128*(n+m) px), plinth, corner posts, a door on the
    down-left face, windows per storey on both visible faces, a gable or flat roof with a small overhang."""
    storey_h = PERSON_TO_STOREY * ACTOR_BU * wall_scale     # 1:3 person:facade per storey -> 2.45 BU
    wall_h = storey_h * storeys
    wall = flat_material("Wall", (0.58, 0.55, 0.50))
    dark = flat_material("Dark", (0.22, 0.20, 0.18))
    roofm = flat_material("Roof", (0.38, 0.36, 0.34))
    trim = flat_material("Trim", (0.30, 0.27, 0.24))
    objs = [add_box("Walls", 0, 0, 0, n, m, wall_h, wall, scene),
            add_box("Plinth", -0.02, -0.02, 0, n + 0.04, m + 0.04, 0.12, dark, scene)]
    for (px, py) in ((0, 0), (n, 0), (0, m), (n, m)):
        objs.append(add_box("Post", px - 0.05, py - 0.05, 0, 0.10, 0.10, wall_h + 0.02, trim, scene))
    for k in range(1, storeys):
        objs.append(add_box("Band", -0.03, -0.03, k * storey_h - 0.04, n + 0.06, m + 0.06, 0.08, trim, scene))
    door_x = n * 0.22
    objs.append(add_box("Door", door_x, -0.03, 0.12, 0.42, 0.06, ACTOR_BU * 1.15, dark, scene))
    for k in range(storeys):
        z = k * storey_h + storey_h * 0.45
        cols = max(1, n - 1)
        for i in range(cols):
            x = (i + 1) * n / (cols + 1)
            if k == 0 and abs(x - (door_x + 0.21)) < 0.5:
                continue
            objs.append(add_box("Win", x - 0.18, -0.03, z, 0.36, 0.06, 0.40, dark, scene))
        rows = max(1, m - 1)
        for j in range(rows):
            y = (j + 1) * m / (rows + 1)
            objs.append(add_box("Win", n - 0.03, y - 0.18, z, 0.06, 0.36, 0.40, dark, scene))
    ov = 0.12
    if roof == "gable":
        rise = 0.45 * min(n, m)
        verts = [(-ov, -ov, wall_h), (n + ov, -ov, wall_h), (n + ov, m + ov, wall_h), (-ov, m + ov, wall_h),
                 (-ov, m / 2.0, wall_h + rise), (n + ov, m / 2.0, wall_h + rise)]
        faces = [(0, 1, 5, 4), (3, 2, 5, 4), (0, 3, 4), (1, 2, 5), (0, 1, 2, 3)]
        mesh = bpy.data.meshes.new("RoofMesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        roof_ob = bpy.data.objects.new("Roof", mesh)
        roof_ob.data.materials.append(roofm)
        scene.collection.objects.link(roof_ob)
        objs.append(roof_ob)
        objs.append(add_box("Ridge", -ov - 0.02, m / 2.0 - 0.04, wall_h + rise - 0.02, n + 2 * ov + 0.04, 0.08, 0.06, trim, scene))
    else:
        objs.append(add_box("RoofSlab", -ov, -ov, wall_h, n + 2 * ov, m + 2 * ov, 0.14, roofm, scene))
        objs.append(add_box("Parapet", -ov, -ov, wall_h + 0.14, n + 2 * ov, 0.08, 0.22, trim, scene))
        objs.append(add_box("Parapet", n + ov - 0.08, -ov, wall_h + 0.14, 0.08, m + 2 * ov, 0.22, trim, scene))
    cube = add_box("Ref_1BU_cube", n + 0.6, -0.4, 0, 1, 1, 1, wall, scene)
    person = add_box("Ref_person_0816BU", n + 0.6, m + 0.3, 0, 0.35, 0.25, ACTOR_BU, dark, scene)
    for ob in (cube, person):
        ob.hide_render = True
    return objs, wall_h


def build_shed(scene, n, m):
    return build_house(scene, n, m, storeys=1, roof="gable")


def build_stair(scene, n, m):
    """The crooked stair: a stone mass with steps rising along +Y (screen up-right) between two parapets."""
    stone = flat_material("Stone", (0.50, 0.50, 0.49))
    dark = flat_material("Dark", (0.22, 0.20, 0.18))
    objs = [add_box("Base", 0, 0, 0, n, m, 0.18, stone, scene)]
    steps = 8
    depth = m / steps
    rise = 0.22
    for i in range(steps):
        objs.append(add_box("Step", 0.18, i * depth, 0.18, n - 0.36, depth, rise * (i + 1), stone, scene))
    top = 0.18 + rise * steps
    objs.append(add_box("ParapetL", 0, 0, 0, 0.18, m, top + 0.25, dark, scene))
    objs.append(add_box("ParapetR", n - 0.18, 0, 0, 0.18, m, top + 0.25, dark, scene))
    objs.append(add_box("Landing", 0.18, m - depth * 1.5, top, n - 0.36, depth * 1.5, 0.06, stone, scene))
    return objs, top


def build_prop(scene, kind):
    """1x1 props, centred on the cell, all under 0.8 BU tall so the plate stays 256x256 (gate 6)."""
    wood = flat_material("Wood", (0.45, 0.34, 0.24))
    darkwood = flat_material("DarkWood", (0.28, 0.21, 0.15))
    stone = flat_material("Stone", (0.50, 0.50, 0.49))
    iron = flat_material("Iron", (0.20, 0.20, 0.21))
    flame = bpy.data.materials.new("Flame")
    flame.use_nodes = True
    nt = flame.node_tree
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (1.0, 0.55, 0.15, 1.0)
    em.inputs[1].default_value = 2.2   # keeps the flame orange under the Standard view transform
    nt.links.new(em.outputs[0], nt.nodes.get("Material Output").inputs[0])
    cx, cy = 0.5, 0.5
    objs = []
    light_point = None

    def cyl(name, r, h, z0, mat, x=cx, y=cy, rot=None):
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=(x, y, z0 + h / 2.0), vertices=24)
        ob = bpy.context.active_object
        ob.name = name
        if rot:
            ob.rotation_euler = rot
        ob.data.materials.append(mat)
        objs.append(ob)
        return ob

    if kind == "barrel":
        cyl("Barrel", 0.27, 0.62, 0, wood)
        cyl("Band", 0.285, 0.04, 0.14, iron)
        cyl("Band", 0.285, 0.04, 0.44, iron)
    elif kind == "crate":
        objs.append(add_box("Crate", cx - 0.3, cy - 0.3, 0, 0.6, 0.6, 0.6, wood, scene))
        for (x, y) in ((cx - 0.3, cy - 0.3), (cx + 0.26, cy - 0.3), (cx - 0.3, cy + 0.26), (cx + 0.26, cy + 0.26)):
            objs.append(add_box("Slat", x, y, 0, 0.04, 0.04, 0.62, darkwood, scene))
        objs.append(add_box("Slat", cx - 0.3, cy - 0.3, 0.58, 0.6, 0.04, 0.04, darkwood, scene))
        objs.append(add_box("Slat", cx - 0.3, cy - 0.3, 0.58, 0.04, 0.6, 0.04, darkwood, scene))
    elif kind == "torch":
        objs.append(add_box("Post", cx - 0.04, cy - 0.04, 0, 0.08, 0.08, 0.62, darkwood, scene))
        cyl("Head", 0.07, 0.10, 0.60, iron)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.075, location=(cx, cy, 0.76), segments=16, ring_count=8)
        fl = bpy.context.active_object
        fl.name = "Flame"
        fl.data.materials.append(flame)
        objs.append(fl)
        light_point = Vector((cx, cy, 0.76))
        empty = bpy.data.objects.new("Light", None)
        empty.location = light_point
        scene.collection.objects.link(empty)
    elif kind == "bollard":
        cyl("Base", 0.18, 0.06, 0, stone)
        cyl("Bollard", 0.13, 0.42, 0.06, iron)
        cyl("Cap", 0.15, 0.04, 0.48, iron)
    elif kind == "well":
        cyl("Wall", 0.36, 0.34, 0, stone)
        cyl("Hole", 0.28, 0.02, 0.34, iron)
        objs.append(add_box("PostA", cx - 0.36, cy - 0.04, 0, 0.07, 0.08, 0.72, darkwood, scene))
        objs.append(add_box("PostB", cx + 0.29, cy - 0.04, 0, 0.07, 0.08, 0.72, darkwood, scene))
        objs.append(add_box("Bar", cx - 0.36, cy - 0.03, 0.66, 0.72, 0.06, 0.06, darkwood, scene))
        objs.append(add_box("Bucket", cx - 0.06, cy - 0.06, 0.42, 0.12, 0.12, 0.12, iron, scene))
    elif kind == "cart":
        objs.append(add_box("Bed", cx - 0.36, cy - 0.22, 0.22, 0.72, 0.44, 0.06, wood, scene))
        for sx in (-0.36, 0.30):
            objs.append(add_box("Side", cx + sx, cy - 0.22, 0.28, 0.06, 0.44, 0.18, darkwood, scene))
        for sy in (-0.22, 0.16):
            objs.append(add_box("End", cx - 0.36, cy + sy, 0.28, 0.72, 0.06, 0.18, darkwood, scene))
        for sy in (-0.27, 0.27):
            cyl("Wheel", 0.19, 0.05, 0.0, darkwood, x=cx + 0.05, y=cy + sy, rot=(math.radians(90), 0, 0))
    return objs, light_point


def screen_extent(scene, cam, objs):
    """(min_v, max_v) of every render-visible vertex in normalised camera space."""
    vs = []
    for ob in objs:
        if ob.hide_render or ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            co = ob.matrix_world @ v.co
            vs.append(world_to_camera_view(scene, cam, co).y)
    return min(vs), max(vs)


def place_foot_at_bottom(scene, cam, n, m, pad_px=1):
    """Shift the camera frame so the footprint's near vertex (n, 0, 0) sits pad_px above the bottom row."""
    res_x, res_y = scene.render.resolution_x, scene.render.resolution_y
    want = pad_px / res_y
    for _ in range(3):
        v = world_to_camera_view(scene, cam, Vector((n, 0.0, 0.0))).y
        delta = want - v
        if abs(delta) * res_y < 0.05:
            break
        cam.data.shift_y -= delta * (res_y / res_x)
    return world_to_camera_view(scene, cam, Vector((n, 0.0, 0.0)))


def main():
    args = parse_args()
    n = args.n
    m = args.m or n
    # Blender's cwd is not the caller's shell cwd; resolve relative --out against this script's folder.
    if not os.path.isabs(args.out):
        args.out = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), args.out))
    if args.save and not os.path.isabs(args.save):
        args.save = os.path.normpath(os.path.join(args.out, args.save))
    os.makedirs(args.out, exist_ok=True)
    scene, ver = fresh_scene()
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = args.samples
    res_x = PX_PER_TILE_W // 2 * (n + m)      # 128·(n+m)
    name = args.name or {"calibration": "calibration_square", "ground": f"ground_{args.variant}",
                         "shed": f"shed_{n}x{m}", "house": f"house_{n}x{m}", "stair": f"stair_{n}x{m}",
                         "prop": f"{args.prop}_1x1"}[args.scene]

    if args.scene in ("calibration", "ground"):
        res_y = PX_PER_TILE_H // 2 * (n + m)  # 64·(n+m): the diamond exactly fills the frame
        cam = add_camera(scene, n, m, res_x, res_y)
        sun, sun_euler = add_sun(scene)
        if args.scene == "calibration":
            mat = flat_material("Calibration", (0.62, 0.62, 0.62))
            add_plane(scene, n, m, 1.0, mat)
        else:
            mat = ground_material(args.variant, args.seed)
            add_plane(scene, n, m, 1.10, mat)   # bleed: colour extends past the diamond, clipped later
        foot = world_to_camera_view(scene, cam, Vector((n, 0.0, 0.0)))
        k = None
    else:
        light_point = None
        if args.scene == "shed":
            objs, _ = build_shed(scene, n, m)
        elif args.scene == "house":
            objs, _ = build_house(scene, n, m, storeys=args.storeys, roof=args.roof, wall_scale=args.wall_scale)
        elif args.scene == "stair":
            objs, _ = build_stair(scene, n, m)
        else:
            n = m = 1
            res_x = PX_PER_TILE_W
            objs, light_point = build_prop(scene, args.prop)
        # provisional frame, measure, then size K and shift the foot to the bottom
        cam = add_camera(scene, n, m, res_x, PX_PER_TILE_H * max(n, m))
        sun, sun_euler = add_sun(scene)
        bpy.context.view_layer.update()          # scale/location set via properties are lazy until this
        lo, hi = screen_extent(scene, cam, objs)
        v_foot = world_to_camera_view(scene, cam, Vector((n, 0.0, 0.0))).y   # the cell's near vertex, pinned at the bottom
        height_px = (hi - v_foot) * scene.render.resolution_y
        k = max(max(n, m), math.ceil((height_px + 6) / PX_PER_TILE_H))
        if args.scene == "prop" and k > 2:
            print(f"WARN prop {args.prop} needs {height_px:.0f} px above the foot -> K={k}; shrink the mesh (gate 6 allows 256x128 or 256x256)")
        scene.render.resolution_y = PX_PER_TILE_H * k
        foot = place_foot_at_bottom(scene, cam, n, m, pad_px=1)

    out_png = os.path.join(args.out, name + ".png")
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)

    if args.save:
        os.makedirs(os.path.dirname(os.path.abspath(args.save)), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.save))

    info = {
        "blender": bpy.app.version_string,
        "engine": scene.render.engine,
        "scene": args.scene,
        "name": name,
        "footprint": [n, m],
        "resolution": [scene.render.resolution_x, scene.render.resolution_y],
        "k": k,
        "camera_euler_deg": list(CAM_EULER_DEG),
        "sensor_fit": cam.data.sensor_fit,
        "ortho_scale": round(cam.data.ortho_scale, 5),
        "shift_y": round(cam.data.shift_y, 5),
        "sun_euler_deg": list(sun_euler),
        "foot_vertex_ndc": [round(foot.x, 4), round(foot.y, 4)],
        "px_per_bu": round(PX_PER_BU, 3),
        "actor_bu": round(ACTOR_BU, 4),
        "out": os.path.relpath(out_png, os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).replace(chr(92), "/"),
    }
    if args.scene == "prop" and light_point is not None:
        lv = world_to_camera_view(scene, cam, light_point)
        info["light_px"] = [round(lv.x * scene.render.resolution_x, 1), round((1.0 - lv.y) * scene.render.resolution_y, 1)]
    with open(os.path.join(args.out, name + ".render.json"), "w", encoding="utf-8") as fh:
        import json
        json.dump(info, fh, indent=2)
    print("DIMETRIC_RENDER " + str(info))


if __name__ == "__main__":
    main()
