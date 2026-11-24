class_name CampTouch
extends Control

var motor: CampThirdPerson
var move_finger := -1
var look_finger := -1
var stick_center := Vector2.ZERO
var stick_offset := Vector2.ZERO
var radius := 57.0
var safe := Rect2()

func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    get_viewport().size_changed.connect(_resize)
    _resize()

func _resize() -> void:
    cancel()
    var viewport_size := get_viewport_rect().size
    var window_size := Vector2(DisplayServer.window_get_size()).max(Vector2.ONE)
    var area := Rect2(DisplayServer.get_display_safe_area())
    # Some Web backends return an empty area until the page is visible.
    if area.size.x <= 0 or area.size.y <= 0:
        area = Rect2(Vector2.ZERO, window_size)
    var scale := viewport_size / window_size
    safe = Rect2(area.position * scale, area.size * scale).intersection(Rect2(Vector2.ZERO, viewport_size))
    if safe.size.x < viewport_size.x * .6 or safe.size.y < viewport_size.y * .6:
        safe = Rect2(Vector2.ZERO, viewport_size)
    radius = clampf(viewport_size.y * .094, 38.0, 64.0)
    stick_center = home()
    queue_redraw()

func home() -> Vector2:
    return Vector2(safe.position.x + radius + radius * .55, safe.end.y - radius - radius * .49)

func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
        cancel()

func _input(event: InputEvent) -> void:
    if not is_instance_valid(motor):
        return
    if event is InputEventScreenTouch and (not event.pressed or event.canceled):
        if event.index == move_finger:
            move_finger = -1
            stick_offset = Vector2.ZERO
            stick_center = home()
            motor.touch_direction = Vector2.ZERO
            queue_redraw()
            get_viewport().set_input_as_handled()
        elif event.index == look_finger:
            look_finger = -1
            if event.canceled:
                motor.cancel_look()
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag and not motor.locked:
        if event.index == move_finger:
            stick_offset = (event.position - stick_center).limit_length(radius)
            var power := clampf((stick_offset.length() / radius - .13) / .87, 0.0, 1.0)
            motor.touch_direction = stick_offset.normalized() * power
            queue_redraw()
            get_viewport().set_input_as_handled()
        elif event.index == look_finger:
            motor.orbit(event.screen_relative)
            get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
    if not is_instance_valid(motor) or motor.locked:
        return
    # The GUI gets first refusal on new fingers. Ownership then survives
    # crossing the split or moving over a button until that finger releases.
    if event is InputEventScreenTouch and event.pressed and not event.canceled:
        if event.position.x < size.x * .47 and event.position.y > size.y * .39 and move_finger < 0:
            move_finger = event.index
            stick_center = event.position
            queue_redraw()
            get_viewport().set_input_as_handled()
        elif event.position.x >= size.x * .47 and look_finger < 0:
            look_finger = event.index
            get_viewport().set_input_as_handled()

func cancel() -> void:
    move_finger = -1
    look_finger = -1
    stick_offset = Vector2.ZERO
    stick_center = home()
    if is_instance_valid(motor):
        motor.clear_controls()
    queue_redraw()

func _draw() -> void:
    if is_instance_valid(motor) and motor.locked:
        return
    draw_circle(stick_center, radius, Color("#0b202466"))
    draw_arc(stick_center, radius, 0.0, TAU, 48, Color("#e7f2da92"), 1.3, true)
    draw_circle(stick_center + stick_offset, radius * .36, Color("#edf5dcac"))
