extends SceneTree
## Standalone Godot 4.7.2 probe. Run with --headless --script.

func _initialize() -> void:
    call_deferred("_probe")

func _probe() -> void:
    var stick := VirtualJoystick.new()
    stick.size = Vector2(240, 240)
    stick.deadzone_ratio = .15
    root.add_child(stick)
    await process_frame
    _touch(0, Vector2(120, 120), true)
    _drag(0, Vector2(120, 90))
    var fixed := Input.get_action_strength("ui_up")
    _touch(1, Vector2(215, 85), true)
    _drag(1, Vector2(220, 20))
    var independent := Input.get_action_strength("ui_up")
    _touch(0, Vector2(120, 90), false, true)
    var canceled := Input.get_action_strength("ui_up")
    _touch(1, Vector2(220, 20), false)
    stick.joystick_mode = VirtualJoystick.JOYSTICK_DYNAMIC
    _touch(2, Vector2(30, 40), true)
    _drag(2, Vector2(55, 40))
    var dynamic := Input.get_action_strength("ui_right")
    stick.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    var focus := Input.get_action_strength("ui_right")
    _touch(2, Vector2(55, 40), false)
    print("Native joystick fixed %.3f | second finger %.3f | canceled %.3f | dynamic %.3f | focus notification %.3f"         % [fixed, independent, canceled, dynamic, focus])
    quit(int(fixed <= .1 or absf(fixed - independent) > .001 or canceled > .001 or dynamic <= .1))

func _touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = point
    event.pressed = pressed
    event.canceled = canceled
    root.push_input(event, true)

func _drag(index: int, point: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = point
    root.push_input(event, true)
