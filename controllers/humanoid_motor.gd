class_name CampHumanoidMotor
extends CampPhysicalMotor

const ACTOR := preload("res://character_lab/actor.gd")
var water_motion: AnimationLibrary
var presentation: Node3D
var motion_clip: StringName = &"Idle"

func _ready() -> void:
    presentation = ACTOR.new()
    presentation.name = "HumanoidVisual"
    presentation.water_motion = water_motion
    add_child(presentation)
    super()

func set_heading(heading: float) -> void:
    super(heading)
    presentation.rotation.y = heading

func walk_direction(desired: Vector3, running: bool, delta: float, animate := true, dive_steer := 0.0) -> void:
    super(desired, running, delta, animate, dive_steer)
    var actual := get_real_velocity()
    var lean := clampf(-actual.y * .28, -.40, .40) if underwater() else 0.0
    presentation.rotation.x = lerpf(presentation.rotation.x, lean, 1.0 - exp(-8.0 * delta))
    if animate:
        var magnitude := Vector2(actual.x, actual.z).length()
        if swimming():
            var stroking := locomotion == Locomotion.SWIM or (underwater()
                and (desired.limit_length().length_squared() > .018 or absf(actual.y) > .14))
            set_motion(&"Swim" if stroking else &"Tread")
        else:
            set_motion(&"Idle" if magnitude < .16 else (&"Jog" if running and magnitude > 2.55 else &"Walk"))
        presentation.match_speed(motion_clip, magnitude)

func set_motion(clip: StringName) -> void:
    if motion_clip != clip:
        motion_clip = clip
        presentation.select(clip)
