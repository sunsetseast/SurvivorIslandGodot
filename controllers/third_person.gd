class_name CampThirdPerson
extends CampHumanoidMotor

const CAMERA_DISTANCE := 4.25
const DEFAULT_PITCH := -.31
const LOOK_GRACE := 2.8

var pivot: Node3D
var camera: Camera3D
var yaw := .48
var pitch := DEFAULT_PITCH
var sensitivity := 1.0
var look_held := false
var touch_direction := Vector2.ZERO
var run_toggled := false
var locked := false
var travel_distance := 0.0
var _look_timer := LOOK_GRACE
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
    _look_timer = LOOK_GRACE
    yaw = wrapf(yaw - relative.x * .0047 * sensitivity, -PI, PI)
    pitch = clampf(pitch - relative.y * .0041 * sensitivity, -1.0, .42)

func reset_camera() -> void:
    if locked:
        return
    yaw = wrapf(travel_heading + PI, -PI, PI)
    pitch = DEFAULT_PITCH
    _look_timer = LOOK_GRACE

func clear_controls() -> void:
    touch_direction = Vector2.ZERO
    look_held = false
    _look_timer = LOOK_GRACE
    run_toggled = false

func _physics_process(delta: float) -> void:
    var previous := global_position
    var input := _local_input()
    var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
    walk_direction(direction, run_toggled or Input.is_physical_key_pressed(KEY_SHIFT), delta, not locked)
    travel_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    _update_camera(input, delta)

func _update_camera(input: Vector2, delta: float) -> void:
    if look_held or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        _look_timer = LOOK_GRACE
    else:
        _look_timer = maxf(0.0, _look_timer - delta)
    if _look_timer <= 0.0 and input.y < -.65 and absf(input.x) < .16:
        var behind := travel_heading + PI
        if absf(angle_difference(yaw, behind)) < .6:
            yaw = rotate_toward(yaw, behind, delta * .35)
    var focus_height := 1.43
    var camera_pitch := pitch
    if swimming():
        focus_height = maxf(1.35, water.level - global_position.y + .47)
    pivot.position.y = lerpf(pivot.position.y, focus_height, 1.0 - exp(-delta * 11.0))
    if locomotion != Locomotion.LAND:
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
    if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
        orbit(event.relative)
    elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
        reset_camera()
