class_name CampHumanoidMotor
extends CharacterBody3D

const ACTOR := preload("res://character_lab/actor.gd")
const RADIUS := 0.36
const WALK_SPEED := 1.96
const RUN_SPEED := 4.52
var presentation: Node3D
var travel_heading := 0.0
var planar := Vector3.ZERO
var motion_clip: StringName = &"Idle"
var _wall_probe := KinematicCollision3D.new()
var _landing_probe := KinematicCollision3D.new()

func _ready() -> void:
    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = RADIUS
    capsule.height = 1.69
    collider.shape = capsule
    collider.position.y = capsule.height * .5
    add_child(collider)
    floor_snap_length = .30
    floor_max_angle = deg_to_rad(42)
    floor_stop_on_slope = true
    floor_constant_speed = false
    safe_margin = .022
    presentation = ACTOR.new()
    presentation.name = "HumanoidVisual"
    add_child(presentation)
    set_heading(rotation.y)
    rotation.y = 0.0

func set_heading(heading: float) -> void:
    travel_heading = heading
    presentation.rotation.y = heading

func face_point(point: Vector3, delta: float) -> void:
    var heading := point - global_position
    if Vector2(heading.x, heading.z).length_squared() > .001:
        travel_heading = rotate_toward(travel_heading, atan2(heading.x, heading.z), 9.0 * delta)
        presentation.rotation.y = travel_heading

func walk_direction(desired: Vector3, running: bool, delta: float, animate := true) -> void:
    var speed := RUN_SPEED if running else WALK_SPEED
    planar = planar.move_toward(desired.limit_length() * speed, delta * (13.0 if desired.is_zero_approx() else 8.5))
    if planar.length_squared() > .022:
        face_point(global_position + planar, delta)
    velocity.x = planar.x
    velocity.z = planar.z
    velocity.y = -.12 if is_on_floor() else maxf(velocity.y - 15.0 * delta, -25.0)
    if is_on_floor() and is_on_wall() and planar.length_squared() > .09:
        _try_step(planar * delta)
    move_and_slide()
    if animate:
        var actual := get_real_velocity()
        var magnitude := Vector2(actual.x, actual.z).length()
        set_motion(&"Idle" if magnitude < .16 else (&"Jog" if running and magnitude > 2.55 else &"Walk"))

func set_motion(clip: StringName) -> void:
    if motion_clip != clip:
        motion_clip = clip
        presentation.select(clip)

func _try_step(travel: Vector3) -> void:
    # Probe the ascent, forward motion and landing with the same capsule used
    # for gameplay. Only short lips or treads can be crossed.
    if not test_move(global_transform, travel, _wall_probe) or _wall_probe.get_normal().y > .5:
        return
    var rise := Vector3.UP * .31
    if test_move(global_transform, rise):
        return
    var raised := global_transform
    raised.origin += rise
    if test_move(raised, travel * 1.5):
        return
    raised.origin += travel * 1.5
    if not test_move(raised, -rise - Vector3.UP * .08, _landing_probe):
        return
    var place := raised.origin + _landing_probe.get_travel()
    if _landing_probe.get_normal().y > .75 and place.y > global_position.y + .025:
        global_position = place
        velocity.y = 0.0
