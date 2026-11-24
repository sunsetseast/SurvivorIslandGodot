class_name CampThirdPerson
extends CampHumanoidMotor

var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var yaw := .48
var pitch := -.31
var touch_direction := Vector2.ZERO
var run_toggled := false
var locked := false
var travel_distance := 0.0

func _ready() -> void:
    collision_layer = 2
    collision_mask = 1 | 4 | 8
    super()
    pivot = Node3D.new()
    pivot.name = "OrbitPivot"
    pivot.position.y = 1.43
    add_child(pivot)
    spring = SpringArm3D.new()
    spring.name = "CameraSpring"
    spring.spring_length = 4.25
    spring.margin = .13
    spring.collision_mask = 1
    var probe := SphereShape3D.new()
    probe.radius = .18
    spring.shape = probe
    pivot.add_child(spring)
    camera = Camera3D.new()
    camera.name = "PlayerCamera"
    camera.fov = 68.0
    camera.near = .08
    camera.far = 270.0
    spring.add_child(camera)
    camera.current = true
    pivot.rotation = Vector3(pitch, yaw, 0)
    set_heading(PI + yaw)

func orbit(relative: Vector2) -> void:
    if locked:
        return
    yaw = wrapf(yaw - relative.x * .0047, -PI, PI)
    pitch = clampf(pitch - relative.y * .0041, -1.0, .42)
    pivot.rotation = Vector3(pitch, yaw, 0)

func clear_controls() -> void:
    touch_direction = Vector2.ZERO
    run_toggled = false

func _physics_process(delta: float) -> void:
    var previous := global_position
    walk_direction(direction(), run_toggled or Input.is_physical_key_pressed(KEY_SHIFT), delta)
    travel_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()

func direction() -> Vector3:
    if locked:
        return Vector3.ZERO
    var x := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
    var z := int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
    var input := (Vector2(x, z) + touch_direction).limit_length()
    return Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
        orbit(event.relative)
