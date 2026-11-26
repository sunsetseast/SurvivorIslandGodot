class_name CampPhysicalMotor
extends CharacterBody3D

const RADIUS := 0.36
const WALK_SPEED := 1.96
const RUN_SPEED := 4.52
enum Locomotion { LAND, WADE, SWIM, TREAD, UNDERWATER }

const WADE_ENTER := .22
const WADE_EXIT := .14
const SWIM_ENTER := 1.24
const SWIM_EXIT := 1.02
const FLOAT_OFFSET := 1.07
const SWIM_SPEED := 2.12
const DIVE_OFFSET := 2.35
const DIVE_MIN_DEPTH := 2.60
const DIVE_SPEED := 1.85

var movement_speed_multiplier := 1.0
# Opt-in transient platform attachment; ordinary camp controllers leave these false.
var raft_attached := false
var locomotion_suspended := false
var water: CampWaterSurface
var locomotion := Locomotion.LAND
var travel_heading := 0.0
var planar := Vector3.ZERO
var dive_requested := false
var _dive_target := 0.0
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
    set_heading(rotation.y)
    rotation.y = 0.0

func set_heading(heading: float) -> void:
    travel_heading = heading

func face_point(point: Vector3, delta: float, turn_rate := 9.0) -> void:
    var heading := point - global_position
    if Vector2(heading.x, heading.z).length_squared() > .001:
        set_heading(rotate_toward(travel_heading, atan2(heading.x, heading.z), turn_rate * delta))

func walk_direction(desired: Vector3, running: bool, delta: float, _animate := true, dive_steer := 0.0) -> void:
    if raft_attached or locomotion_suspended:
        velocity = Vector3.ZERO
        planar = Vector3.ZERO
        return
    _update_water_state(desired)
    var speed := RUN_SPEED if running else WALK_SPEED
    var acceleration := 8.5
    var braking := 13.0
    if swimming():
        speed = DIVE_SPEED if underwater() else SWIM_SPEED
        acceleration = 4.5
        braking = 6.2
    elif locomotion == Locomotion.WADE:
        var drag := smoothstep(WADE_EXIT, SWIM_ENTER, water.depth_at(global_position))
        speed *= lerpf(.89, .39, drag)
    speed *= movement_speed_multiplier
    var input := desired.limit_length()
    _steer_planar(input, speed, acceleration, braking, delta)
    velocity.x = planar.x
    velocity.z = planar.z
    if swimming():
        # Keep the capsule on the same collision layers as on land. A gradual
        # approach to sloping ground can lift the body via normal slide contacts.
        var target := water.level - FLOAT_OFFSET
        if underwater() and dive_requested:
            var bed := water.level - water.depth_at(global_position)
            _dive_target = clampf(_dive_target + dive_steer * delta * 1.65,
                bed + .12, water.level - DIVE_OFFSET)
            target = _dive_target
        var vertical_limit := 1.7 if underwater() else 3.2
        velocity.y = move_toward(velocity.y,
            clampf((target - global_position.y) * 7.0, -vertical_limit, vertical_limit), delta * 22.0)
    else:
        velocity.y = -.12 if is_on_floor() else maxf(velocity.y - 15.0 * delta, -25.0)
        if is_on_floor() and is_on_wall() and planar.length_squared() > .09:
            _try_step(planar * delta)
    move_and_slide()

func _steer_planar(input: Vector3, speed: float, acceleration: float, braking: float, delta: float) -> void:
    var reversing := planar.dot(input) < 0.0
    if input.length_squared() > .012:
        face_point(global_position + input, delta, 10.0 if swimming() else 16.0)
    planar = planar.move_toward(input * speed, delta * (braking if reversing or input.is_zero_approx() else acceleration))

func swimming() -> bool:
    return locomotion >= Locomotion.SWIM

func underwater() -> bool:
    return locomotion == Locomotion.UNDERWATER

func can_dive() -> bool:
    return swimming() and water.depth_at(global_position) >= DIVE_MIN_DEPTH

func toggle_dive() -> void:
    if dive_requested:
        dive_requested = false
    elif can_dive():
        dive_requested = true
        _dive_target = minf(global_position.y, water.level - DIVE_OFFSET)

func restore_dive(active: bool) -> void:
    dive_requested = active
    _dive_target = global_position.y

func _update_water_state(desired: Vector3) -> void:
    if water == null:
        return
    var depth := water.depth_at(global_position)
    var near_water := global_position.y <= water.level + .12
    var was_swimming := swimming()
    if depth < DIVE_MIN_DEPTH:
        dive_requested = false
    var surfacing := underwater() and global_position.y < water.level - FLOAT_OFFSET - .09
    if near_water and depth >= SWIM_EXIT and (dive_requested or surfacing):
        locomotion = Locomotion.UNDERWATER
    elif near_water and depth >= (SWIM_EXIT if was_swimming else SWIM_ENTER):
        # A small speed deadband lets a released stroke finish into the tread.
        var stroking := desired.length_squared() > .018 or planar.length_squared() > .09
        locomotion = Locomotion.SWIM if stroking else Locomotion.TREAD
    elif near_water and depth > (WADE_ENTER if locomotion == Locomotion.LAND else WADE_EXIT):
        locomotion = Locomotion.WADE
    else:
        locomotion = Locomotion.LAND
    floor_snap_length = 0.0 if swimming() else .30
    if was_swimming and not swimming():
        velocity.y = minf(velocity.y, 0.0)

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

func steer_player(input: Vector3, speed: float, acceleration: float, braking: float, delta: float) -> void:
    if input.is_zero_approx():
        planar = planar.move_toward(Vector3.ZERO, braking * delta)
        return
    var goal := atan2(input.x, input.z)
    var current_speed := planar.length()
    # Brake before a reversal, then steer velocity along the visible heading.
    # Smaller turns stay in motion and accelerate as the heading lines up.
    if absf(angle_difference(travel_heading, goal)) > PI * .5 and current_speed > .12:
        planar = planar.move_toward(Vector3.ZERO, braking * 2.0 * delta)
        return
    set_heading(rotate_toward(travel_heading, goal, (13.0 if swimming() else 20.0) * delta))
    var alignment := maxf(0.0, cos(angle_difference(travel_heading, goal)))
    var target_speed := input.length() * speed * alignment
    var rate := braking if target_speed < current_speed else acceleration
    planar = Vector3(sin(travel_heading), 0, cos(travel_heading)) * move_toward(
        current_speed, target_speed, rate * delta)
