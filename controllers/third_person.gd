class_name CampThirdPerson
extends CampHumanoidMotor

const CAMERA_DISTANCE := 4.25
const DEFAULT_PITCH := -.31
const LOOK_RADIANS_PER_SHORT_EDGE := 2.07
# Thresholds apply after the touch HUD's radial dead zone.
const STICK_ENGAGE := .08
const STICK_NEUTRAL := .03
const CAMERA_STEER_RATE := 1.65
const MobileOrbit := preload("res://controllers/mobile_orbit_camera.gd")

var pivot: Node3D
var camera: Camera3D
var yaw := .48
var pitch := DEFAULT_PITCH
var sensitivity := 1.0
var camera_relative_steering := false
var controller_b := false
var raw_look := Vector2.ZERO
var last_swipe := Vector2.ZERO
var touch_direction := Vector2.ZERO:
    set(value):
        touch_direction = value.limit_length()
        var strength := touch_direction.length()
        if strength <= STICK_NEUTRAL or locked:
            _stick_active = false
        elif not _stick_active and strength >= STICK_ENGAGE:
            _stick_active = true
            _stick_yaw = rendered_yaw()
            _stick_follows_camera = camera_relative_steering
var run_toggled := false
var locked := false
var travel_distance := 0.0
var movement_intent := Vector3.ZERO
var _stick_active := false
var _stick_yaw := 0.0
var _stick_follows_camera := false
var _pending_look := Vector2.ZERO
var _reset_requested := false
var _camera_distance := CAMERA_DISTANCE
var _camera_probe := PhysicsShapeQueryParameters3D.new()
var _mobile_orbit: MobileOrbit
var _previous_rendered_yaw := 0.0
var _orbit_steers := false

func _ready() -> void:
    collision_layer = 2
    collision_mask = 1 | 4 | 8
    super()
    pivot = Node3D.new()
    pivot.name = "OrbitPivot"
    pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
    pivot.position.y = 1.43
    add_child(pivot)
    var probe := SphereShape3D.new()
    probe.radius = .22
    _camera_probe.shape = probe
    _camera_probe.collision_mask = 1
    camera = Camera3D.new()
    camera.name = "PlayerCamera"
    camera.fov = 68.0
    camera.near = .08
    camera.far = 270.0
    pivot.add_child(camera)
    camera.position.z = CAMERA_DISTANCE
    camera.current = true
    pivot.rotation = Vector3(pitch, yaw, 0)
    set_heading(PI + yaw)

func orbit(relative: Vector2) -> void:
    if locked:
        return
    _pending_look += relative

func reset_camera() -> void:
    _reset_requested = not locked

func cancel_look() -> void:
    _pending_look = Vector2.ZERO

func clear_controls() -> void:
    touch_direction = Vector2.ZERO
    movement_intent = Vector3.ZERO
    cancel_look()
    _reset_requested = false
    run_toggled = false
    _orbit_steers = false
    if controller_b:
        # Focus loss must not replay a queued orbit on resume.
        yaw = _mobile_orbit.rendered_yaw
        pitch = _mobile_orbit.rendered_pitch
        _mobile_orbit.sync(yaw, pitch, pivot.global_position.y - global_position.y, camera.position.z)

func _physics_process(delta: float) -> void:
    if not controller_b:
        _apply_look()
    var previous := global_position
    var input := _local_input()
    movement_intent = Vector3(input.x, 0, input.y).rotated(Vector3.UP, _movement_yaw(delta))
    walk_direction(movement_intent, run_toggled or Input.is_physical_key_pressed(KEY_SHIFT), delta,
        not locked, sin(pitch) * maxf(0.0, -input.y))
    travel_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    if not controller_b:
        _update_camera(delta)

func _process(delta: float) -> void:
    if not controller_b:
        return
    _apply_look()
    var body_position := get_global_transform_interpolated().origin
    var surface := water.level if locomotion != Locomotion.LAND else -INF
    _mobile_orbit.update(body_position, _focus_height(body_position.y), yaw, pitch, delta,
        CAMERA_DISTANCE, surface, underwater())

func _apply_look() -> void:
    if _reset_requested:
        yaw = rendered_yaw() + angle_difference(rendered_yaw(), travel_heading + PI) if controller_b \
            else wrapf(travel_heading + PI, -PI, PI)
        pitch = DEFAULT_PITCH
        _reset_requested = false
        _orbit_steers = false
    # Unscaled drag deltas and the backing window share the same units.
    # B uses viewport-space deltas and the same viewport's short edge.
    var screen := get_viewport().get_visible_rect().size if controller_b else Vector2(DisplayServer.window_get_size())
    var short_edge := minf(screen.x, screen.y)
    if short_edge <= 1.0:
        var viewport := get_viewport().get_visible_rect().size
        short_edge = maxf(1.0, minf(viewport.x, viewport.y))
    var radians_per_pixel := LOOK_RADIANS_PER_SHORT_EDGE * sensitivity / short_edge
    raw_look = _pending_look
    if not raw_look.is_zero_approx():
        last_swipe = raw_look
    yaw -= _pending_look.x * radians_per_pixel
    if not controller_b:
        yaw = wrapf(yaw, -PI, PI)
    elif not is_zero_approx(_pending_look.x):
        _orbit_steers = true
    pitch = clampf(pitch - _pending_look.y * radians_per_pixel * .87, -1.0, .70 if underwater() else .42)
    _pending_look = Vector2.ZERO

func _movement_yaw(delta: float) -> float:
    if not controller_b:
        return _stick_yaw if _stick_active and not _stick_follows_camera else yaw
    var view := rendered_yaw()
    var increment := view - _previous_rendered_yaw
    _previous_rendered_yaw = view
    if not _stick_active:
        return view
    if _stick_follows_camera and _orbit_steers:
        # Slow orbits steer continuously. Large swipes nudge the bearing and
        # discard the excess, so a fast glance cannot build a steering backlog.
        var limit := CAMERA_STEER_RATE * delta
        _stick_yaw += clampf(increment, -limit, limit)
    return _stick_yaw

func rendered_yaw() -> float:
    return _mobile_orbit.rendered_yaw if controller_b else yaw

func camera_obstructed() -> bool:
    return _mobile_orbit.obstructed if controller_b else _camera_distance < CAMERA_DISTANCE - .01

func select_controller(use_b: bool) -> void:
    if controller_b == use_b:
        return
    var view := rendered_yaw()
    var view_pitch := pitch if not controller_b else _mobile_orbit.rendered_pitch
    var height := pivot.global_position.y - global_position.y
    controller_b = use_b
    yaw = view if use_b else wrapf(view, -PI, PI)
    pitch = view_pitch
    pivot.top_level = use_b
    physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if use_b else Node.PHYSICS_INTERPOLATION_MODE_OFF
    reset_physics_interpolation()
    if use_b:
        if _mobile_orbit == null:
            _mobile_orbit = MobileOrbit.new()
            _mobile_orbit.setup(pivot, camera, CAMERA_DISTANCE)
        _mobile_orbit.sync(yaw, pitch, height, camera.position.z)
        _previous_rendered_yaw = yaw
    else:
        pivot.position = Vector3.UP * height
        pivot.rotation = Vector3(pitch, yaw, 0)
        _camera_distance = camera.position.z

func sync_camera() -> void:
    reset_physics_interpolation()
    if controller_b:
        _mobile_orbit.sync(yaw, pitch, _focus_height(global_position.y), CAMERA_DISTANCE)
        _previous_rendered_yaw = yaw

func _focus_height(body_y: float) -> float:
    if underwater():
        return 1.06
    if swimming():
        return maxf(1.35, water.level - body_y + .47)
    return 1.43

func _update_camera(delta: float) -> void:
    var focus_height := _focus_height(global_position.y)
    var camera_pitch := pitch
    pivot.position.y = lerpf(pivot.position.y, focus_height, 1.0 - exp(-delta * 11.0))
    if locomotion != Locomotion.LAND and not underwater():
        var clearance := global_position.y + pivot.position.y - water.level - .21
        camera_pitch = minf(pitch, asin(clampf(clearance / CAMERA_DISTANCE, -.2, .42)))
    pivot.rotation = Vector3(camera_pitch, yaw, 0)
    _camera_probe.transform.origin = pivot.global_position
    _camera_probe.motion = pivot.global_basis.z * CAMERA_DISTANCE
    var fractions := get_world_3d().direct_space_state.cast_motion(_camera_probe)
    var limit := CAMERA_DISTANCE
    if not fractions.is_empty():
        limit = maxf(.06, fractions[0] * CAMERA_DISTANCE - .075)
    var target := limit - .16 if limit < CAMERA_DISTANCE else limit
    var rate := 22.0 if target < _camera_distance else 5.5
    _camera_distance = minf(limit, lerpf(_camera_distance, maxf(.06, target), 1.0 - exp(-delta * rate)))
    camera.position.z = _camera_distance

func _local_input() -> Vector2:
    if locked:
        return Vector2.ZERO
    if _stick_active:
        var strength := inverse_lerp(STICK_NEUTRAL, 1.0, touch_direction.length())
        return touch_direction.normalized() * strength
    var x := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
    var z := int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
    return Vector2(x, z).limit_length()

func _steer_planar(input: Vector3, speed: float, acceleration: float, braking: float, delta: float) -> void:
    if locked:
        planar = Vector3.ZERO
        return
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

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
        if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
            orbit(event.relative if controller_b else event.screen_relative)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_R:
            reset_camera()
        elif event.physical_keycode == KEY_SPACE and not locked:
            toggle_dive()
