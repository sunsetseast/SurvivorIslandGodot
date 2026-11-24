"""Bake the two shared swim loops from UAL Standard onto the existing public rig.

Open Maeve.blend from the Phase 1 source archive, then run this script in Blender
with arguments after --: the UAL Godot Standard GLB and an output GLB.
The output is an intermediate used to extract an AnimationLibrary in Godot.
"""
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).parent))
from retarget import bake

source, output = sys.argv[sys.argv.index("--") + 1:]
armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
bake(armature, Path(source), {"Swim": "Swim_Fwd_Loop", "Tread": "Swim_Idle_Loop"})
for obj in bpy.context.scene.objects:
    obj.select_set(obj.type in {"MESH", "ARMATURE"})
bpy.context.view_layer.objects.active = armature
bpy.ops.export_scene.gltf(filepath=output, use_selection=True, export_format="GLB",
                         export_animation_mode="NLA_TRACKS", export_frame_range=False,
                         export_optimize_animation_size=True)
