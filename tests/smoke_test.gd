extends SceneTree
## Run after import: godot --headless --path . --script res://tests/smoke_test.gd

func _initialize() -> void:
    call_deferred("_test_scene")

func _test_scene() -> void:
    var scene_resource := load("res://scenes/main.tscn") as PackedScene
    if scene_resource == null:
        _fail("Could not load main scene")
        return
    var instance := scene_resource.instantiate()
    root.add_child(instance)
    var player := instance.get_node_or_null("Player") as CharacterBody3D
    var camera := instance.get_node_or_null("Camera3D") as Camera3D
    var hud := instance.get_node_or_null("HUDLayer/TouchHUD") as Control
    if player == null or camera == null or hud == null or not instance.has_node("BeachTerrain"):
        _fail("Scene must provide the player, camera, beach and touch HUD")
        return
    await _physics_frames(40)
    if not player.is_on_floor() or not camera.current:
        _fail("Player must settle on the beach under the active camera")
        return

    var screen_size := root.get_visible_rect().size
    var left := screen_size * Vector2(0.10, 0.25)
    var right := screen_size * Vector2(0.75, 0.25)
    var swipe := Vector2(100.0, 0.0)
    var camera_start := camera.position - player.position

    _touch(0, left, true)
    _touch(1, screen_size * Vector2(0.25, 0.30), true)
    _drag(1, left, swipe)
    await _physics_frames(15)
    if absf((camera.position - player.position).x - camera_start.x) > 0.01:
        _fail("A second touch on the left must not take over the camera")
        return

    var player_start := player.position
    _touch(2, right, true)
    _drag(0, left, Vector2(0.0, -100.0))
    _drag(2, right, swipe)
    await _physics_frames(30)
    if player.position.distance_to(player_start) < 0.5:
        _fail("Left thumb must move the player during a two-finger gesture")
        return
    if absf((camera.position - player.position).x - camera_start.x) < 0.5:
        _fail("Right thumb must orbit the camera during a two-finger gesture")
        return

    _touch(0, left, true, true)
    _touch(2, right, false)
    await _physics_frames(2)
    var stopped_at := player.position
    await _physics_frames(12)
    if not stopped_at.is_equal_approx(player.position):
        _fail("Canceling the left touch must stop movement")
        return
    print("PASS: Phase 0 scene, floor, active camera, independent dual-touch input and cancellation")
    quit(0)

func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = position
    event.pressed = pressed
    event.canceled = canceled
    root.push_input(event, true)

func _drag(index: int, origin: Vector2, distance: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = origin + distance
    event.relative = distance
    root.push_input(event, true)

func _physics_frames(count: int) -> void:
    for frame in range(count):
        await physics_frame

func _fail(message: String) -> void:
    push_error(message)
    quit(1)
