"""Build the editable Maeve study and its runtime GLB in Blender 4.3."""
import argparse
from pathlib import Path
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from retarget import bake

MPFB = "bl_ext.user_default.mpfb"
FACE = {
    "head/head-rectangular": 0.27,
    "head/head-age-incr": 0.25,
    "chin/chin-width-decr": 0.35,
    "chin/chin-prominent-incr": 0.42,
    "nose/nose-curve-convex": 0.64,
    "nose/nose-point-width-decr": 0.36,
    "nose/nose-flaring-incr": 0.16,
    "cheek/l-cheek-bones-incr": 0.41,
    "cheek/r-cheek-bones-incr": 0.32,
    "cheek/l-cheek-inner-incr": 0.28,
    "cheek/r-cheek-inner-incr": 0.36,
    "eyebrows/eyebrows-trans-forward": 0.34,
    "forehead/forehead-temple-decr": 0.24,
    "eyes/l-eye-corner2-up": 0.20,
    "eyes/r-eye-corner2-up": 0.12,
    "eyes/l-eye-bag-height-incr": 0.24,
    "eyes/r-eye-bag-height-incr": 0.19,
    "mouth/mouth-cupidsbow-incr": 0.37,
    "mouth/mouth-lowerlip-volume-incr": 0.24,
    "ears/l-ear-flap-incr": 0.16,
}
SMILE = {
    "mouth/mouth-angles-up": 0.73,
    "mouth/mouth-dimples-in": 0.20,
    "cheek/l-cheek-trans-up": 0.15,
    "cheek/r-cheek-trans-up": 0.19,
}


def resized_image(path, size):
    image = bpy.data.images.load(str(path), check_existing=False)
    if max(image.size) > size:
        scale = size / max(image.size)
        image.scale(round(image.size[0] * scale), round(image.size[1] * scale))
    return image


def save_pixels(image, pixels):
    image.pixels.foreach_set(pixels.reshape(-1))
    image.update()
    image.pack()


def pbr(name, color, roughness, image=None, blend=None, normal=None):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Specular IOR Level"].default_value = 0.28
    if image:
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        links.new(node.outputs["Color"], shader.inputs["Base Color"])
        if blend is not None:
            material.use_backface_culling = False
            material.surface_render_method = "DITHERED"
            cutoff = nodes.new("ShaderNodeMath")
            cutoff.operation = "GREATER_THAN"
            cutoff.inputs[1].default_value = blend
            links.new(node.outputs["Alpha"], cutoff.inputs[0])
            links.new(cutoff.outputs[0], shader.inputs["Alpha"])
    if normal:
        normal.colorspace_settings.name = "Non-Color"
        node = nodes.new("ShaderNodeTexImage")
        node.image = normal
        mapping = nodes.new("ShaderNodeNormalMap")
        mapping.inputs["Strength"].default_value = 0.5
        links.new(node.outputs["Color"], mapping.inputs["Color"])
        links.new(mapping.outputs["Normal"], shader.inputs["Normal"])
    return material


def paint(image, style):
    width, height = image.size
    values = np.zeros(width * height * 4, np.float32)
    image.pixels.foreach_get(values)
    pixels = values.reshape(height, width, 4)
    rgb = pixels[:, :, :3]
    if style == "copper":
        rgb[:] = np.clip(rgb * (1.24, 0.91, 0.70) + (0.035, 0.009, 0.003), 0, 1)
    elif style == "denim":
        rgb[:] = np.clip(rgb * (0.63, 0.72, 0.72), 0, 1)
    else:
        y, x = np.mgrid[:height, :width]
        weave = 0.025 * np.cos(x * 2.9) * np.cos(y * 2.9) + 0.014 * np.sin(x * 0.092 + y * 0.064)
        rgb[:] = (0.22, 0.44, 0.39) + weave[:, :, None]
        pixels[:, :, 3] = 1
    save_pixels(image, pixels)
    return image


def assign(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = True


def coat_patch(outfit, rig):
    """Add a sewn chest tab fitted to the deformed garment surface."""
    positions = [v.co.copy() for v in outfit.data.vertices]
    bvh = BVHTree.FromPolygons(positions, [p.vertices[:] for p in outfit.data.polygons])
    tree = KDTree(len(positions))
    for index, coord in enumerate(positions):
        tree.insert(coord, index)
    tree.balance()

    def project(x, z, gap):
        point, normal, _, _ = bvh.ray_cast(Vector((x, -0.6, z)), Vector((0, 1, 0)))
        if point is None:
            raise RuntimeError("Chest patch missed the fitted garment")
        return point + normal * gap

    rows = [[project(0.067 + x * 0.006, 1.153 + z * 0.006, 0.0025)
             for x in range(7)] for z in range(5)]
    points = [p for row in rows for p in row]
    faces = [(y * 7 + x, y * 7 + x + 1, (y + 1) * 7 + x + 1, (y + 1) * 7 + x)
             for y in range(4) for x in range(6)]
    mesh = bpy.data.meshes.new("Woven chest tab")
    mesh.from_pydata(points, [], faces)
    obj = bpy.data.objects.new("Seamed chest tab", mesh)
    bpy.context.collection.objects.link(obj)
    assign(obj, pbr("Field tab • weathered canvas", (0.20, 0.10, 0.042), 0.9))
    edge = pbr("Field tab • thread", (0.55, 0.34, 0.13), 0.83)
    obj.data.materials.append(edge)
    for face in obj.data.polygons:
        if face.index // 6 in (0, 3) or face.index % 6 in (0, 5):
            face.material_index = 1
    weights = {group.index: obj.vertex_groups.new(name=group.name) for group in outfit.vertex_groups
               if group.name in rig.data.bones}
    for vertex in mesh.vertices:
        _, near_index, _ = tree.find(vertex.co)
        for weight in outfit.data.vertices[near_index].groups:
            if weight.group in weights:
                weights[weight.group].add([vertex.index], weight.weight, "REPLACE")
    obj.parent = rig
    mod = obj.modifiers.new("Skin", "ARMATURE")
    mod.object = rig


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--system-assets", type=Path, required=True)
    args.add_argument("--motions", type=Path, required=True)
    args.add_argument("--glb", type=Path, required=True)
    args.add_argument("--blend", type=Path, required=True)
    config = args.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assets = config.system_assets.resolve()

    bpy.ops.preferences.addon_enable(module=MPFB)
    from bl_ext.user_default.mpfb.entities.clothes.mhclo import Mhclo
    from bl_ext.user_default.mpfb.services.clothesservice import ClothesService
    from bl_ext.user_default.mpfb.services.humanservice import HumanService
    from bl_ext.user_default.mpfb.services.locationservice import LocationService
    from bl_ext.user_default.mpfb.services.objectservice import ObjectService
    from bl_ext.user_default.mpfb.services.targetservice import TargetService

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    phenotype = TargetService.get_default_macro_info_dict()
    phenotype.update(gender=0.0, age=0.54, muscle=0.29, weight=0.58,
                     height=0.45, proportions=0.45, cupsize=0.29)
    body = HumanService.create_human(macro_detail_dict=phenotype)
    body.name = "Maeve skin"

    def targets(values):
        for name, weight in values.items():
            path = Path(LocationService.get_mpfb_data("targets")) / (name + ".target.gz")
            TargetService.load_target(body, str(path), weight=weight, name=name.split("/")[-1])

    targets(FACE)
    TargetService.bake_targets(body)
    rig = HumanService.add_builtin_rig(body, "game_engine")
    rig.name = "Maeve Rig"

    def fit(relative, name, material, mask_body=False):
        source = Mhclo()
        source.load(str(assets / (relative + ".mhclo")))
        mesh = source.load_mesh(bpy.context)
        mesh.name = name
        ClothesService.fit_clothes_to_human(mesh, body, source)
        mesh.location = (0, 0, 0)
        ClothesService.set_up_rigging(body, mesh, rig, source, import_subrig=False, import_weights=False)
        assign(mesh, material)
        if mask_body:
            hidden.update(source.delverts)
        return mesh

    hidden = set()
    skin_file = "skins/middleage_caucasian_female/middleage_lightskinned_female_diffuse.png"
    assign(body, pbr("Skin • warm matte", (0.45, 0.23, 0.15), 0.57,
                     resized_image(assets / skin_file, 1024)))
    fit("eyes/low-poly/low-poly", "Hazel eyes", pbr("Hazel iris and sclera", (0.25, 0.17, 0.06), 0.22,
        resized_image(assets / "eyes/materials/brownlight_eye.png", 256)))
    for directory, name in (("eyebrows", "eyebrow001"), ("eyelashes", "eyelashes01")):
        stem = f"{directory}/{name}/{name}"
        fit(stem, directory.title(), pbr(directory.title(), (0.07, 0.033, 0.02), 0.78,
            resized_image(assets / (stem + ".png"), 256), blend=0.33))
    hair_stem = "hair/bob01/bob01"
    hair = fit(hair_stem, "Asymmetric copper bob", pbr("Hair • chestnut copper", (0.16, 0.06, 0.025), 0.60,
        paint(resized_image(assets / (hair_stem + "_diffuse.png"), 1024), "copper"), blend=0.33))
    for vertex in hair.data.vertices:
        x, y, z = vertex.co
        vertex.co.x *= 1.035
        # Give the swept locks room above the left orbit while keeping the side and nape long.
        front = max(0, min(1, (-y - 0.050) / 0.036))
        sweep = max(0, min(1, (0.046 - x) / 0.085))
        lift = 0.88 * max(0, 1.492 - z) * front * sweep
        vertex.co.z += 0.002 + lift
        vertex.co.y -= lift * 0.10
    ObjectService.activate_blender_object(hair, deselect_all=True)
    decimation = hair.modifiers.new("Groom silhouette reduction", "DECIMATE")
    decimation.ratio = 0.65
    bpy.ops.object.modifier_move_up(modifier=decimation.name)
    bpy.ops.object.modifier_apply(modifier=decimation.name)
    outfit_stem = "clothes/female_casualsuit01/female_casualsuit01"
    normal = resized_image(assets / (outfit_stem + "_normal.png"), 512)
    outfit = fit(outfit_stem, "Field jersey and jeans", pbr("Jersey • woven spruce", (0.06, 0.18, 0.13), 0.89,
        paint(resized_image(assets / (outfit_stem + "_diffuse.png"), 512), "jersey"), normal=normal), True)
    denim = pbr("Denim • washed indigo", (0.09, 0.16, 0.20), 0.86,
        paint(resized_image(assets / (outfit_stem + "_diffuse.png"), 1024), "denim"), normal=normal)
    outfit.data.materials.append(denim)
    pending = set(range(len(outfit.data.vertices)))
    adjacency = {vertex: [] for vertex in pending}
    for edge in outfit.data.edges:
        first, second = edge.vertices
        adjacency[first].append(second)
        adjacency[second].append(first)
    lower = set()
    while pending:
        start = pending.pop()
        component = [start]
        for vertex in component:
            neighbors = [other for other in adjacency[vertex] if other in pending]
            component.extend(neighbors)
            pending.difference_update(neighbors)
        if min(outfit.data.vertices[i].co.z for i in component) < 0.6:
            lower.update(component)
    for polygon in outfit.data.polygons:
        if polygon.vertices[0] in lower:
            polygon.material_index = 1
    shoe = "clothes/shoes02/shoes02"
    shoes = fit(shoe, "Trail shoes", pbr("Traction shoe • leather and rubber", (0.12, 0.11, 0.09), 0.71,
        resized_image(assets / (shoe + "_diffuse.png"), 512)), True)
    shoe_geometry = bmesh.new()
    shoe_geometry.from_mesh(shoes.data)
    bmesh.ops.delete(shoe_geometry, geom=[v for v in shoe_geometry.verts if v.co.z > 0.117],
                     context="VERTS")
    shoe_geometry.to_mesh(shoes.data)
    shoe_geometry.free()
    coat_patch(outfit, rig)

    # Preserve the fitted MPFB topology where it is visible and remove helpers/covered skin.
    targets(SMILE)
    smile = body.shape_key_add(name="Smile", from_mix=True)
    for key in list(body.data.shape_keys.key_blocks)[1:]:
        if key != smile:
            body.shape_key_remove(key)
    body.modifiers.remove(body.modifiers["Hide helpers"])
    human_group = body.vertex_groups["body"].index
    keep = {v.index for v in body.data.vertices if any(g.group == human_group for g in v.groups)}
    deform = bmesh.new()
    deform.from_mesh(body.data)
    remove = [v for v in deform.verts if v.index not in keep or v.index in hidden]
    bmesh.ops.delete(deform, geom=remove, context="VERTS")
    deform.to_mesh(body.data)
    deform.free()
    ObjectService.activate_blender_object(body, deselect_all=True)
    bpy.context.view_layer.update()

    bake(rig, config.motions.resolve())
    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type in {"MESH", "ARMATURE"})
    bpy.context.view_layer.objects.active = rig
    config.blend.parent.mkdir(parents=True, exist_ok=True)
    config.glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(config.blend.resolve()), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(config.glb.resolve()), use_selection=True,
                             export_format="GLB", export_texcoords=True, export_normals=True,
                             export_animations=True, export_animation_mode="NLA_TRACKS",
                             export_force_sampling=True, export_frame_range=False,
                             export_optimize_animation_size=True, export_morph=True)


if __name__ == "__main__":
    main()
