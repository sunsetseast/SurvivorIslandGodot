class_name SurvivorMenuScroll
extends ScrollContainer
## The game disables touch-to-mouse emulation. Handle scroll drags within this
## menu while leaving taps and gameplay touch events on their existing paths.

var _finger := -1
var _start_y := 0.0
var _start_scroll := 0
var _dragging := false

func _input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventScreenTouch:
        if event.pressed and not event.canceled and _finger < 0:
            var bar := get_v_scroll_bar()
            if bar.max_value <= bar.page or not get_global_rect().has_point(event.position):
                return
            _finger = event.index
            _start_y = _local_y(event.position)
            _start_scroll = scroll_vertical
        elif event.index == _finger and (not event.pressed or event.canceled):
            if event.canceled:
                cancel_touch()
                return
            if _dragging:
                propagate_notification(NOTIFICATION_SCROLL_END)
            # The drag canceled the button press. Let the viewport receive the
            # release so it can clear GUI touch focus for this finger.
            _finger = -1
            _dragging = false
    elif event is InputEventScreenDrag and event.index == _finger:
        var travel := _start_y - _local_y(event.position)
        if not _dragging:
            if absf(travel) < 8.0:
                return
            _dragging = true
            propagate_notification(NOTIFICATION_SCROLL_BEGIN)
        scroll_vertical = _start_scroll + roundi(travel)
        get_viewport().set_input_as_handled()

func cancel_touch() -> void:
    if _finger < 0:
        return
    if not _dragging:
        propagate_notification(NOTIFICATION_SCROLL_BEGIN)
    propagate_notification(NOTIFICATION_SCROLL_END)
    _finger = -1
    _dragging = false

func _local_y(point: Vector2) -> float:
    return (get_global_transform_with_canvas().affine_inverse() * point).y

static func edit_on_touch(event: InputEvent, field: LineEdit) -> void:
    if event is InputEventScreenTouch and event.pressed:
        field.grab_focus()
        field.edit()
        field.accept_event()
