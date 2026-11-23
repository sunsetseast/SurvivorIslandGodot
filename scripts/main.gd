extends Node3D
## Phase 0: original, intentionally primitive geometry. Not a character-art demonstration.

const WALK_SPEED: float = 5.0
const GRAVITY: float = 18.0
const TOUCH_RADIUS: float = 70.0
const CAMERA_DISTANCE: float = 6.0

var _player: CharacterBody3D
var _camera: Camera3D
var _hud: Control
var _debug_label: Label
var _yaw: float = 0.0
var _pitch: float = 0.24
var _left_finger: int = -1
var _right_finger: int = -1
var _touch_origin: Vector2 = Vector2.ZERO
var _touch_direction: Vector2 = Vector2.ZERO
var _status_seconds: float = 0.0

func _ready() -> void:
    _make_environment()
    _make_island()
    _make_player()
    _make_camera()
    _make_hud()
    _update_camera(1.0)

func _make_environment() -> void:
    var world_environment := WorldEnvironment.new()
    world_environment.name = "WorldEnvironment"
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.50, 0.74, 0.85)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.89, 0.94, 1.0)
    env.ambient_light_energy = 0.85
    world_environment.environment = env
    add_child(world_environment)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-52.0, 24.0, -10.0)
    sun.light_energy = 1.05
    sun.shadow_enabled = false # First test favors compatibility, not visual fidelity.
    add_child(sun)

func _material(color: Color, roughness_value: float = 0.9) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness_value
    return material

func _mesh_instance(mesh: Mesh, material: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = pos
    parent.add_child(instance)
    return instance

func _make_island() -> void:
    var sand_mesh := PlaneMesh.new()
    sand_mesh.size = Vector2(70.0, 70.0)
    var sand := _mesh_instance(sand_mesh, _material(Color(0.77, 0.68, 0.49)), self, Vector3.ZERO)
    sand.name = "BeachTerrain"

    var ground_body := StaticBody3D.new()
    ground_body.name = "BeachCollision"
    ground_body.position = Vector3(0.0, -0.4, 0.0)
    add_child(ground_body)
    var ground_collision := CollisionShape3D.new()
    var ground_shape := BoxShape3D.new()
    ground_shape.size = Vector3(70.0, 0.8, 70.0)
    ground_collision.shape = ground_shape
    ground_body.add_child(ground_collision)

    var sea_mesh := PlaneMesh.new()
    sea_mesh.size = Vector2(130.0, 60.0)
    _mesh_instance(sea_mesh, _material(Color(0.11, 0.49, 0.57), 0.38), self, Vector3(0.0, -0.17, -64.0))

    var tree_points := [
        Vector3(-23.0, 0.0, -22.0), Vector3(-18.0, 0.0, -26.0),
        Vector3(19.0, 0.0, -25.0), Vector3(24.0, 0.0, -14.0),
        Vector3(-26.0, 0.0, 1.0), Vector3(25.0, 0.0, 11.0),
        Vector3(-19.0, 0.0, 25.0), Vector3(20.0, 0.0, 26.0)
    ]
    for i in range(tree_points.size()):
        _make_tree(tree_points[i], 0.9 + float(i % 3) * 0.18)

    var cliff_points := [Vector3(-42.0, 0.0, -48.0), Vector3(-34.0, 0.0, -56.0), Vector3(42.0, 0.0, -52.0)]
    for i in range(cliff_points.size()):
        var rock := CylinderMesh.new()
        rock.top_radius = 3.8 + float(i)
        rock.bottom_radius = 7.0 + float(i)
        rock.height = 24.0 + float(i) * 6.0
        rock.radial_segments = 9
        _mesh_instance(rock, _material(Color(0.41, 0.45, 0.38)), self, cliff_points[i] + Vector3(0.0, rock.height / 2.0 - 1.0, 0.0))

    var campfire := CylinderMesh.new()
    campfire.top_radius = 0.5
    campfire.bottom_radius = 0.65
    campfire.height = 0.24
    _mesh_instance(campfire, _material(Color(0.40, 0.27, 0.18)), self, Vector3(3.5, 0.14, -4.5))
    var flame := SphereMesh.new()
    flame.radius = 0.36
    flame.height = 0.72
    _mesh_instance(flame, _material(Color(1.0, 0.45, 0.06)), self, Vector3(3.5, 0.55, -4.5))

func _make_tree(pos: Vector3, scale_factor: float) -> void:
    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.16 * scale_factor
    trunk.bottom_radius = 0.29 * scale_factor
    trunk.height = 4.1 * scale_factor
    trunk.radial_segments = 6
    _mesh_instance(trunk, _material(Color(0.32, 0.22, 0.13)), self, pos + Vector3(0.0, trunk.height / 2.0, 0.0))
    var canopy := SphereMesh.new()
    canopy.radius = 2.1 * scale_factor
    canopy.height = 2.5 * scale_factor
    canopy.radial_segments = 8
    canopy.rings = 4
    _mesh_instance(canopy, _material(Color(0.16, 0.38, 0.23)), self, pos + Vector3(0.0, 4.6 * scale_factor, 0.0))

func _make_player() -> void:
    _player = CharacterBody3D.new()
    _player.name = "Player"
    _player.position = Vector3(0.0, 2.0, 8.0)
    add_child(_player)

    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.36
    capsule.height = 1.8
    collision.shape = capsule
    collision.position = Vector3(0.0, 0.91, 0.0)
    _player.add_child(collision)

    var body_mesh := CapsuleMesh.new()
    body_mesh.radius = 0.33
    body_mesh.height = 1.38
    _mesh_instance(body_mesh, _material(Color(0.88, 0.33, 0.22)), _player, Vector3(0.0, 1.05, 0.0))
    var head := SphereMesh.new()
    head.radius = 0.28
    head.height = 0.55
    _mesh_instance(head, _material(Color(0.69, 0.44, 0.31)), _player, Vector3(0.0, 1.76, 0.0))
    var face_direction := BoxMesh.new()
    face_direction.size = Vector3(0.25, 0.12, 0.10)
    _mesh_instance(face_direction, _material(Color(0.18, 0.15, 0.13)), _player, Vector3(0.0, 1.71, -0.27))

func _make_camera() -> void:
    _camera = Camera3D.new()
    _camera.name = "Camera3D"
    _camera.current = true
    _camera.fov = 67.0
    _camera.far = 160.0
    add_child(_camera)

func _make_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "HUDLayer"
    add_child(canvas)
    _hud = Control.new()
    _hud.name = "TouchHUD"
    _hud.set_script(load("res://scripts/touch_hud.gd"))
    canvas.add_child(_hud)

    var heading := Label.new()
    heading.text = "SURVIVOR ISLAND  |  GODOT PHASE 0"
    heading.position = Vector2(20.0, 12.0)
    heading.add_theme_font_size_override("font_size", 23)
    heading.add_theme_color_override("font_color", Color(1, 1, 1))
    heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud.add_child(heading)

    var subtitle := Label.new()
    subtitle.text = "Feasibility test — placeholder character, NOT final art"
    subtitle.position = Vector2(20.0, 43.0)
    subtitle.add_theme_font_size_override("font_size", 16)
    subtitle.add_theme_color_override("font_color", Color(0.96, 0.97, 0.87))
    subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud.add_child(subtitle)

    _debug_label = Label.new()
    _debug_label.position = Vector2(20.0, 73.0)
    _debug_label.add_theme_font_size_override("font_size", 16)
    _debug_label.add_theme_color_override("font_color", Color(1, 1, 1))
    _debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud.add_child(_debug_label)

    var instructions := Label.new()
    instructions.text = "Left thumb: move  |  Right thumb: look  |  Desktop: WASD + right-drag"
    instructions.add_theme_font_size_override("font_size", 15)
    instructions.add_theme_color_override("font_color", Color(1, 1, 1))
    instructions.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud.add_child(instructions)
    instructions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    instructions.position = Vector2(200.0, _hud.size.y - 35.0)

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and not event.canceled:
            var on_left: bool = event.position.x < get_viewport().get_visible_rect().size.x * 0.5
            if on_left and _left_finger == -1:
                _left_finger = event.index
                _touch_origin = event.position
                _touch_direction = Vector2.ZERO
                _hud.call("set_stick", _touch_origin, _touch_direction, true)
            elif not on_left and _right_finger == -1:
                _right_finger = event.index
        else:
            if event.index == _left_finger:
                _left_finger = -1
                _touch_direction = Vector2.ZERO
                _hud.call("set_stick", _touch_origin, _touch_direction, false)
            if event.index == _right_finger:
                _right_finger = -1
    elif event is InputEventScreenDrag:
        if event.index == _left_finger:
            _touch_direction = ((event.position - _touch_origin) / TOUCH_RADIUS).limit_length(1.0)
            _hud.call("set_stick", _touch_origin, _touch_direction, true)
        elif event.index == _right_finger:
            _adjust_look(event.relative)
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        _adjust_look(event.relative)

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_hud):
        _left_finger = -1
        _right_finger = -1
        _touch_direction = Vector2.ZERO
        _hud.call("set_stick", _touch_origin, _touch_direction, false)

func _adjust_look(delta_position: Vector2) -> void:
    _yaw -= delta_position.x * 0.004
    _pitch = clampf(_pitch + delta_position.y * 0.003, -0.22, 0.75)

func _movement_axis() -> Vector2:
    var axis := _touch_direction
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        axis.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        axis.x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        axis.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        axis.y += 1.0
    return axis.limit_length(1.0)

func _physics_process(delta: float) -> void:
    if not is_instance_valid(_player):
        return
    var axis := _movement_axis()
    var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
    var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
    var movement := (right * axis.x - forward * axis.y).limit_length(1.0)
    _player.velocity.x = movement.x * WALK_SPEED
    _player.velocity.z = movement.z * WALK_SPEED
    if not _player.is_on_floor():
        _player.velocity.y -= GRAVITY * delta
    else:
        _player.velocity.y = 0.0
    _player.move_and_slide()
    if movement.length_squared() > 0.02:
        _player.rotation.y = lerp_angle(_player.rotation.y, atan2(-movement.x, -movement.z), minf(1.0, delta * 9.0))
    _update_camera(delta)
    _status_seconds += delta
    if _status_seconds > 0.35:
        _status_seconds = 0.0
        _debug_label.text = "FPS: %d   |   Position: %.1f, %.1f, %.1f" % [int(Engine.get_frames_per_second()), _player.position.x, _player.position.y, _player.position.z]

func _update_camera(delta: float) -> void:
    if not is_instance_valid(_player) or not is_instance_valid(_camera):
        return
    var target_position := _player.global_position + Vector3(sin(_yaw) * CAMERA_DISTANCE, 2.6 + sin(_pitch) * 4.0, cos(_yaw) * CAMERA_DISTANCE)
    var follow_factor := minf(1.0, delta * 8.0)
    _camera.global_position = _camera.global_position.lerp(target_position, follow_factor)
    _camera.look_at(_player.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)
