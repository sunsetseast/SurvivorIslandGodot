extends Control
## Draw-only touch joystick. Input is handled by main.gd so it works with multitouch.

var joystick_position: Vector2 = Vector2.ZERO
var joystick_vector: Vector2 = Vector2.ZERO
var active: bool = false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_stick(position: Vector2, direction: Vector2, touching: bool) -> void:
    joystick_position = position
    joystick_vector = direction.limit_length(1.0)
    active = touching
    queue_redraw()

func _draw() -> void:
    var base: Vector2 = joystick_position
    if not active:
        base = Vector2(108.0, get_viewport_rect().size.y - 108.0)
    draw_circle(base, 69.0, Color(0.05, 0.15, 0.17, 0.27))
    draw_arc(base, 69.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.6), 3.0, true)
    draw_circle(base + joystick_vector * 46.0, 27.0, Color(0.95, 0.98, 1.0, 0.63))
    draw_arc(base + joystick_vector * 46.0, 27.0, 0.0, TAU, 32, Color(0.12, 0.24, 0.27, 0.6), 2.0, true)
