extends Node3D

const MODEL = preload("res://character_lab/assets/maeve.glb")
const REFERENCE_SPEEDS := {&"Walk": 1.96, &"Jog": 4.52, &"Swim": 2.12}
const CLIPS := [&"Idle", &"Walk", &"Jog", &"Talk", &"SitDown", &"Seated", &"StandUp"]

var water_motion: AnimationLibrary
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

    var clips: Array = CLIPS.duplicate()
    if water_motion != null:
        player.add_animation_library(&"water", water_motion)
        clips.append_array([&"Swim", &"Tread"])
    var machine := AnimationNodeStateMachine.new()
    for index in clips.size():
        var clip: StringName = clips[index]
        var animation_name := StringName("water/" + clip) if index >= CLIPS.size() else clip
        var animation := player.get_animation(animation_name)
        if clip not in [&"SitDown", &"StandUp"]:
            animation.loop_mode = Animation.LOOP_LINEAR
        var state := AnimationNodeAnimation.new()
        state.animation = animation_name
        var node: AnimationRootNode = state
        if clip in [&"Walk", &"Jog", &"Swim"]:
            var blend := AnimationNodeBlendTree.new()
            blend.add_node(&"Clip", state, Vector2(0, 100))
            blend.add_node(&"Rate", AnimationNodeTimeScale.new(), Vector2(190, 100))
            blend.connect_node(&"Rate", 0, &"Clip")
            blend.connect_node(&"output", 0, &"Rate")
            node = blend
        machine.add_node(clip, node, Vector2(175 + (index % 4) * 175, 80 + (index / 4) * 125))
    for from: StringName in clips:
        for to: StringName in clips:
            if from == to:
                continue
            var transition := AnimationNodeStateMachineTransition.new()
            transition.xfade_time = .18 if to in [&"Idle", &"Walk", &"Jog"] else .24
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

func match_speed(clip: StringName, speed: float) -> void:
    if REFERENCE_SPEEDS.has(clip):
        tree.set("parameters/%s/Rate/scale" % clip, clampf(speed / REFERENCE_SPEEDS[clip], .22, 1.22))

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
