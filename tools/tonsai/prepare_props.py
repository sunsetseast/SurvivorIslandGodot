"""Build the small, diffuse-only camp props from Poly Haven's 1K glTF downloads."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import bpy
from mathutils import Vector

source, output = (Path(path).resolve() for path in sys.argv[sys.argv.index("--") + 1:])
# Dimensions in metres. The long trunk axis is placed along local X.
assets = {
    "dead_tree_trunk_02": ("seating_log", (1.0, .62, .68), 2500),
    "tree_stump_01": ("seat_stump", (.75, .53, .70), 1000),
    "coast_land_rocks_03": ("shore_rock", (1.0, .66, .86), 750),
    "wooden_bucket_01": ("well_bucket", (.45, .44, .42), 1200),
}

for slug, (name, size, budget) in assets.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    directory = source / slug
    document = json.loads((directory / f"{slug}.gltf").read_text())
    # Omit normal and ARM textures for small, rough, diffuse props.
    for material in document["materials"]:
        material.pop("normalTexture", None)
        material.pop("occlusionTexture", None)
        pbr = material["pbrMetallicRoughness"]
        pbr.pop("metallicRoughnessTexture", None)
        pbr["roughnessFactor"] = 1
    with tempfile.TemporaryDirectory(dir=directory) as scratch:
        staged = Path(scratch)
        for buffer in document["buffers"]:
            (staged / buffer["uri"]).symlink_to(directory / buffer["uri"])
        index = document["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        image = document["images"][document["textures"][index]["source"]]
        texture = directory / image["uri"]
        image["uri"] = "albedo.jpg"
        subprocess.run(["convert", str(texture), "-resize", "512x512>", "-quality", "84",
                        str(staged / image["uri"])], check=True)
        clean = staged / "prop.gltf"
        clean.write_text(json.dumps(document))
        bpy.ops.import_scene.gltf(filepath=str(clean))
        for image_data in bpy.data.images:
            if image_data.source == "FILE" and not image_data.packed_file:
                image_data.pack()
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for part in parts:
        part.select_set(True)
    mesh = parts[0]
    bpy.context.view_layer.objects.active = mesh
    if len(parts) > 1:
        bpy.ops.object.join()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    modifier = mesh.modifiers.new("Web triangle budget", "DECIMATE")
    modifier.ratio = min(1, budget / len(mesh.data.polygons))
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    # Blender Z is Godot Y. Reorient the log if its long axis is Blender Y.
    if name == "seating_log" and mesh.dimensions.y > mesh.dimensions.x:
        for vertex in mesh.data.vertices:
            vertex.co.x, vertex.co.y = vertex.co.y, -vertex.co.x
    low = Vector(
        [min(v.co[i] for v in mesh.data.vertices) for i in range(3)])
    high = Vector([max(v.co[i] for v in mesh.data.vertices) for i in range(3)])
    base = (high + low) * .5
    base.z = low.z
    meters = Vector((size[0], size[2], size[1]))
    for vertex in mesh.data.vertices:
        for axis in range(3):
            vertex.co[axis] = (vertex.co[axis] - base[axis]) * meters[axis] / (high[axis] - low[axis])
    mesh.name = name
    bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"), export_format="GLB",
                             export_image_format="JPEG", export_jpeg_quality=82)
