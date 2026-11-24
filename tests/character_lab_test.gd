extends SceneTree

const LAB = preload("res://character_lab/lab.tscn")
const REQUIRED := [&"Idle", &"Walk", &"Jog", &"Talk", &"SitDown", &"Seated", &"StandUp"]

var failures: Array[String] = []

func _initialize() -> void:
    _test.call_deferred()

func _check(condition: bool, description: String) -> void:
    if not condition:
        failures.append(description)

func _test() -> void:
    var lab := LAB.instantiate()
    root.add_child(lab)
    await process_frame
    var actor: Node3D = lab.subject
    _check(actor.skeleton.get_bone_count() >= 45, "Humanoid skeleton imported")
    _check(is_instance_valid(actor.face), "Smile morph imported")
    var skin_count := 0
    for node in actor.find_children("*", "MeshInstance3D", true, false):
        if node.skin and node.skin.get_bind_count() >= 45:
            skin_count += 1
    _check(skin_count >= 3, "Body and garments have weighted skins")
    var shin: int = actor.skeleton.find_bone("calf_l")
    _check(shin >= 0, "Left calf exists")
    for clip in REQUIRED:
        _check(actor.player.has_animation(clip), "Clip imported: %s" % clip)
        actor.playback.start(clip)
        await create_timer(0.09).timeout
        _check(actor.playback.get_current_node() == clip, "Tree plays %s" % clip)
    actor.playback.start(&"Walk")
    await create_timer(0.12).timeout
    var before: Transform3D = actor.skeleton.get_bone_global_pose(shin)
    await create_timer(0.27).timeout
    _check(not actor.skeleton.get_bone_global_pose(shin).is_equal_approx(before), "Walk deforms actual rig")
    actor.playback.start(&"SitDown")
    await create_timer(actor.player.get_animation(&"SitDown").length + 0.2).timeout
    _check(actor.playback.get_current_node() == &"Seated", "Sit enters seated loop")
    actor.select(&"StandUp")
    await create_timer(actor.player.get_animation(&"StandUp").length + 0.45).timeout
    _check(actor.playback.get_current_node() == &"Idle", "Stand returns to idle")
    lab.set_view("Face")
    var face_distance: float = lab.camera.position.distance_to(Vector3(0, 1.39, 0.045))
    _check(face_distance < 0.95, "Face camera has close framing")
    lab.subject.smile_enabled = true
    await create_timer(0.32).timeout
    _check(actor.face.get_blend_shape_value(actor.face.find_blend_shape_by_name(&"Smile")) > 0.5, "Smile is applied to the skinned mesh")
    lab.set_view("Explore")
    var start: Vector3 = lab.runner.position
    var touch := InputEventScreenTouch.new()
    touch.index = 7
    touch.position = Vector2(240, 430)
    touch.pressed = true
    lab._unhandled_input(touch)
    var drag := InputEventScreenDrag.new()
    drag.index = 7
    drag.position = Vector2(240, 350)
    lab._unhandled_input(drag)
    await create_timer(0.55).timeout
    _check(lab.runner.position.distance_to(start) > 0.45, "Touch stick moves the capsule and actor")
    _check(lab.runner.position.y > -0.07, "Actor remains on the collision floor")
    _check(lab.camera.position.distance_to(lab.runner.position) < 4.0, "Camera follows the actor")
    touch.pressed = false
    lab._input(touch)
    _check(lab.stick == Vector2.ZERO, "Touch release clears movement")
    lab.set_count(6)
    _check(lab.copies.get_child_count() == 5, "Six-rig preset")
    lab.set_count(18)
    _check(lab.copies.get_child_count() == 17, "Eighteen-rig preset")
    lab.set_count(1)
    _check(lab.copies.get_child_count() == 0, "Solo preset removes duplicate rigs")
    for failure in failures:
        push_error(failure)
    if failures.is_empty():
        print("Character lab smoke tests passed: skinned asset, seven motion clips, transitions, smile, touch, camera and load presets")
    quit(0 if failures.is_empty() else 1)
