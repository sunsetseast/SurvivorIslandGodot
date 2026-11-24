extends Node3D

const MODEL = preload("res://character_lab/assets/maeve.glb")
const CLIPS := [&"Idle", &"Walk", &"Jog", &"Talk", &"SitDown", &"Seated", &"StandUp"]

var player: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var skeleton: Skeleton3D
var face: MeshInstance3D
var _smile_index := -1
var smile_enabled := false

func _ready() -> void:
    var rig := MODEL.instantiate() as Node3D
    add_child(rig)
    player = rig.find_children("*", "AnimationPlayer", true, false)[0]
    skeleton = rig.find_children("*", "Skeleton3D", true, false)[0]
    for node in rig.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        var index := mesh_instance.find_blend_shape_by_name(&"Smile")
        if index >= 0:
            face = mesh_instance
            _smile_index = index
            break

    var machine := AnimationNodeStateMachine.new()
    for index in CLIPS.size():
        var clip: StringName = CLIPS[index]
        var animation := player.get_animation(clip)
        if clip not in [&"SitDown", &"StandUp"]:
            animation.loop_mode = Animation.LOOP_LINEAR
        var state := AnimationNodeAnimation.new()
        state.animation = clip
        machine.add_node(clip, state, Vector2(175 + (index % 4) * 175, 80 + (index / 4) * 125))
    for from_index in CLIPS.size():
        for to_index in CLIPS.size():
            if from_index == to_index:
                continue
            var transition := AnimationNodeStateMachineTransition.new()
            transition.xfade_time = 0.18 if to_index < 3 else 0.24
            var from: StringName = CLIPS[from_index]
            var to: StringName = CLIPS[to_index]
            if (from == &"SitDown" and to == &"Seated") or (from == &"StandUp" and to == &"Idle"):
                transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
                transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
            machine.add_transition(from, to, transition)
    tree = AnimationTree.new()
    tree.tree_root = machine
    add_child(tree)
    tree.anim_player = tree.get_path_to(player)
    tree.root_node = tree.get_path_to(rig)
    tree.active = true
    playback = tree.get("parameters/playback")
    playback.start(&"Idle")

func select(clip: StringName) -> void:
    if playback.get_current_node() != clip:
        playback.travel(clip)

func pose(clip: StringName, time: float) -> void:
    tree.active = false
    player.play(clip)
    player.seek(time, true)
    player.pause()

func _process(delta: float) -> void:
    if is_instance_valid(face):
        var value := face.get_blend_shape_value(_smile_index)
        var target := 0.8 if smile_enabled else 0.0
        face.set_blend_shape_value(_smile_index, move_toward(value, target, delta * 3.5))
