"""Bake a small Quaternius library onto the fitted MakeHuman armature."""
import math

import bpy
from mathutils import Matrix, Quaternion

CLIPS = {
    "Idle": "Idle_Loop",
    "Walk": "Walk_Loop",
    "Jog": "Jog_Fwd_Loop",
    "Talk": "Idle_Talking_Loop",
    "SitDown": "Sitting_Enter",
    "Seated": "Sitting_Idle_Loop",
    "StandUp": "Sitting_Exit",
}
TORSO = {
    "pelvis": "DEF-hips", "spine_01": "DEF-spine.001",
    "spine_02": "DEF-spine.002", "spine_03": "DEF-spine.003",
    "neck_01": "DEF-neck", "head": "DEF-head",
}
LIMBS = {
    "clavicle": "shoulder", "upperarm": "upper_arm", "lowerarm": "forearm",
    "hand": "hand", "thigh": "thigh", "calf": "shin", "foot": "foot", "ball": "toe",
}


def bake(armature, source_path, clips=CLIPS):
    scene = bpy.context.scene
    scene.render.fps = 30
    previous = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(source_path))
    imported = set(bpy.data.objects) - previous
    donor = next(obj for obj in imported if obj.type == "ARMATURE")
    names = dict(TORSO)
    for side in ("l", "r"):
        names.update({f"{target}_{side}": f"DEF-{source}.{side.upper()}"
                      for target, source in LIMBS.items()})
        for finger in ("thumb", "index", "middle", "ring", "pinky"):
            donor_prefix = "thumb" if finger == "thumb" else "f_" + finger
            for joint in range(1, 4):
                names[f"{finger}_{joint:02}_{side}"] = f"DEF-{donor_prefix}.{joint:02}.{side.upper()}"

    correction = {}
    for name, source_name in names.items():
        bone = armature.data.bones[name]
        source_bone = donor.data.bones[source_name]
        if name.startswith(("upperarm_", "lowerarm_", "hand_", "thigh_", "calf_",
                            "thumb_", "index_", "middle_", "ring_", "pinky_")):
            if name.startswith("hand_"):
                side = name[-1]
                direction = armature.data.bones[f"middle_01_{side}"].head_local - bone.head_local
                source_direction = donor.data.bones[f"DEF-f_middle.01.{side.upper()}"].head_local - source_bone.head_local
            else:
                direction = bone.tail_local - bone.head_local
                source_direction = source_bone.tail_local - source_bone.head_local
            # The donor rests in T-pose. Pre-align anatomical directions before transferring the world rotation.
            alignment = direction.normalized().rotation_difference(source_direction.normalized()).to_matrix()
        else:
            alignment = Matrix.Identity(3)
        correction[name] = source_bone.matrix_local.to_3x3().inverted() @ alignment @ bone.matrix_local.to_3x3()

    armature.animation_data_create()
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)
    for track in list(donor.animation_data.nla_tracks):
        donor.animation_data.nla_tracks.remove(track)

    for name, source in clips.items():
        donor_action = bpy.data.actions[source + "_Rig"]
        donor.animation_data.action = donor_action
        action = bpy.data.actions.new(name)
        armature.animation_data.action = action
        frame_count = math.ceil(donor_action.frame_range[1])
        previous_rotation = {}
        for frame in range(frame_count + 1):
            donor_frame = min(frame, float(donor_action.frame_range[1]))
            scene.frame_set(int(donor_frame), subframe=donor_frame % 1)
            poses = {}
            for bone in armature.pose.bones:
                rest = bone.bone.matrix_local
                parents = {}
                if bone.parent:
                    parents = {
                        "parent_matrix": poses[bone.parent.name],
                        "parent_matrix_local": bone.parent.bone.matrix_local,
                    }

                if bone.name in names:
                    donor_bone = donor.pose.bones[names[bone.name]]
                    rotation = donor_bone.matrix.to_3x3().normalized() @ correction[bone.name]
                    default_pose = bone.bone.convert_local_to_pose(Matrix.Identity(4), rest, **parents)
                    target = rotation.to_4x4()
                    target.translation = default_pose.translation
                    if bone.name == "pelvis":
                        translation = donor_bone.matrix.translation - donor_bone.bone.head_local
                        target.translation += translation * 0.87
                        target.translation.z -= 0.009
                    local = bone.bone.convert_local_to_pose(target, rest, invert=True, **parents)
                    orientation = local.to_quaternion()
                    if bone.name.startswith(("thumb_", "index_", "middle_", "ring_", "pinky_")):
                        orientation = Quaternion().slerp(orientation, 0.72)
                    if bone.name in previous_rotation:
                        orientation.make_compatible(previous_rotation[bone.name])
                    previous_rotation[bone.name] = orientation.copy()
                    bone.rotation_mode = "QUATERNION"
                    bone.rotation_quaternion = orientation
                    bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
                    if bone.name == "pelvis":
                        bone.location = local.translation
                        bone.keyframe_insert("location", frame=frame, group=bone.name)
                    poses[bone.name] = bone.bone.convert_local_to_pose(bone.matrix_basis, rest, **parents)
                else:
                    poses[bone.name] = bone.bone.convert_local_to_pose(Matrix.Identity(4), rest, **parents)
        for fcurve in action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "LINEAR"

        armature.animation_data.action = None
        track = armature.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, action)
        track.mute = True

    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        if action.name not in clips:
            bpy.data.actions.remove(action)
    scene.frame_set(0)
