class_name CampThirdPerson
extends CampHumanoidMotor

const CAMERA_DISTANCE := 4.25
const DEFAULT_PITCH := -.31
const LOOK_RADIANS_PER_SHORT_EDGE := 2.07

var pivot: Node3D
var camera: Camera3D
var yaw := .48
var pitch := DEFAULT_PITCH
var sensitivity := 1.0
var touch_direction := Vector2.ZERO
var run_toggled := false
var locked := false
var travel_distance := 0.0
var _pending_look := Vector2.ZERO
var _reset_requested := false
var _camera_distance := CAMERA_DISTANCE
var _camera_probe := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
    collision_layer = 2
    collision_mask = 1 | 4 | 8
    super()
    pivot = Node3D.new()
    pivot.name = "OrbitPivot"
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

func clear_controls() -> void:
    touch_direction = Vector2.ZERO
    _pending_look = Vector2.ZERO
    _reset_requested = false
    run_toggled = false

func _physics_process(delta: float) -> void:
    if _reset_requested:
        yaw = wrapf(travel_heading + PI, -PI, PI)
        pitch = DEFAULT_PITCH
        _reset_requested = false
    # Unscaled drag deltas and the backing window share the same units.
    var screen := DisplayServer.window_get_size()
    var short_edge := minf(screen.x, screen.y)
    if short_edge <= 1.0:
        var viewport := get_viewport().get_visible_rect().size
        short_edge = maxf(1.0, minf(viewport.x, viewport.y))
    var radians_per_pixel := LOOK_RADIANS_PER_SHORT_EDGE * sensitivity / short_edge
    yaw = wrapf(yaw - _pending_look.x * radians_per_pixel, -PI, PI)
    pitch = clampf(pitch - _pending_look.y * radians_per_pixel * .87, -1.0, .70 if underwater() else .42)
    _pending_look = Vector2.ZERO
    var previous := global_position
    var input := _local_input()
    var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
    walk_direction(direction, run_toggled or Input.is_physical_key_pressed(KEY_SHIFT), delta,
        not locked, sin(pitch) * maxf(0.0, -input.y))
    travel_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    _update_camera(delta)

func _update_camera(delta: float) -> void:
    var focus_height := 1.43
    var camera_pitch := pitch
    if underwater():
        focus_height = 1.06
    elif swimming():
        focus_height = maxf(1.35, water.level - global_position.y + .47)
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
    var x := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
    var z := int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
    return (Vector2(x, z) + touch_direction).limit_length()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
        if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
            orbit(event.screen_relative)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_R:
            reset_camera()
        elif event.physical_keycode == KEY_SPACE and not locked:
            toggle_dive()
