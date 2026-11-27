class_name MarooningTouch
extends CampTouch
var movement_available := true
func _unhandled_input(event: InputEvent) -> void:
    if not movement_available and event is InputEventScreenTouch and event.position.x<size.x*.47: return
    super(event)
func _draw() -> void:
    if movement_available: super()
func set_movement(value: bool) -> void:
    if movement_available==value: return
    movement_available=value
    cancel()
