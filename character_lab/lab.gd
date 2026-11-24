extends Node3D

const ACTOR = preload("res://character_lab/actor.gd")
const STICK_HUD = preload("res://scripts/touch_hud.gd")
const WALK_SPEED := 1.4
const JOG_SPEED := 2.65
const TURNS := [0.0, 42.0, 90.0, 180.0]
const POSES := ["Idle", "Walk", "Jog", "Talk", "Sit", "Seated", "Stand"]

var subject: Node3D
var runner: CharacterBody3D
var camera: Camera3D
var copies: Node3D
var count := 1
var view := "Body"
var selected_clip: StringName = &"Idle"
var yaw := 0.0
var pitch := 0.20
var warm := false
var jog := false
var shadows := false
var turn_index := 1
var stick := Vector2.ZERO
var _stick_origin := Vector2.ZERO
var _left_finger := -1
var _right_finger := -1
var _buttons: Dictionary[String, Button] = {}
var _environment: Environment
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _hud: Control
var _stick_hud: Control
var _status: Label
var _hint: Label
var _seat: MeshInstance3D
var _status_timer := 0.0
var _qa := false
var _review_callback: JavaScriptObject
var _left_panel: Control
var _right_panel: Control
var _previous_mouse_emulation := false

func _enter_tree() -> void:
    _previous_mouse_emulation = Input.emulate_mouse_from_touch
    Input.emulate_mouse_from_touch = true

func _exit_tree() -> void:
    Input.emulate_mouse_from_touch = _previous_mouse_emulation
    if is_instance_valid(_review_callback):
        JavaScriptBridge.eval("delete window.characterLabReview; delete window.characterLabMetrics", true)

func _ready() -> void:
    _build_stage()
    _build_controls()
    set_view("Body")
    set_light(false)
    if OS.has_feature("web"):
        var window := JavaScriptBridge.get_interface("window")
        if is_instance_valid(window) and "?review" in String(window.location.search):
            _review_callback = JavaScriptBridge.create_callback(_review)
            window.characterLabReview = _review_callback
    var args := OS.get_cmdline_user_args()
    if args.has("--capture"):
        _capture(args[args.find("--capture") + 1])

func _build_stage() -> void:
    var world := WorldEnvironment.new()
    _environment = Environment.new()
    _environment.background_mode = Environment.BG_COLOR
    _environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    world.environment = _environment
    add_child(world)
    _key = _light(Vector3(-32, -32, 0), 1.08)
    _fill = _light(Vector3(-28, 123, 0), 0.47)
    _box("Floor", Vector3(36, 0.16, 36), Vector3(0, -0.09, 0), Color("#353f40"), true)
    _disc(Vector3(0, -0.008, 0), 1.17, Color("#455354"))
    for index in range(-4, 5):
        _box("Tick", Vector3(0.025, 0.006, 0.22), Vector3(index * 1.15, -0.005, -2.8), Color("#596d68"))
    _seat = _box("Seat", Vector3(0.65, 0.44, 0.44), Vector3(0, 0.22, -0.16), Color("#777261"))
    _seat.hide()
    runner = CharacterBody3D.new()
    runner.name = "Runner"
    add_child(runner)
    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.24
    capsule.height = 1.54
    collider.shape = capsule
    collider.position.y = 0.78
    runner.add_child(collider)
    subject = ACTOR.new()
    subject.name = "Maeve"
    runner.add_child(subject)
    copies = Node3D.new()
    copies.name = "LoadTest"
    add_child(copies)
    camera = Camera3D.new()
    camera.near = 0.035
    camera.current = true
    add_child(camera)

func _light(angles: Vector3, energy: float) -> DirectionalLight3D:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = angles
    light.light_energy = energy
    add_child(light)
    return light

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.88
    return material

func _box(label: String, size: Vector3, at: Vector3, color: Color, collide := false) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = label
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.material_override = _material(color)
    node.position = at
    add_child(node)
    if collide:
        var body := StaticBody3D.new()
        var collider := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collider.shape = shape
        node.add_child(body)
        body.add_child(collider)
    return node

func _disc(at: Vector3, radius: float, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = 0.01
    mesh.radial_segments = 64
    node.mesh = mesh
    node.material_override = _material(color)
    node.position = at
    add_child(node)
    return node

func _build_controls() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    _hud = Control.new()
    canvas.add_child(_hud)
    _hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stick_hud = STICK_HUD.new()
    _hud.add_child(_stick_hud)

    var style := StyleBoxFlat.new()
    style.bg_color = Color("#102225e8")
    style.border_color = Color("#618582")
    style.set_border_width_all(1)
    style.set_corner_radius_all(10)
    for side in [SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM, SIDE_LEFT]:
        style.set_content_margin(side, 12)
    var left := _panel(style, false)
    var right := _panel(style, true)
    _label(left, "CHARACTER LAB", 21, Color("#e9f3e9"))
    _label(left, "Maeve  /  field study", 16, Color("#b7d4cb"))
    _section(left, "CAMERA")
    for camera_view in ["Face", "Body", "Explore"]:
        _button(left, camera_view, set_view.bind(camera_view), true)
    _button(left, "Rotate", _next_angle)
    _section(right, "ANIMATION")
    var poses := _grid(right)
    for index in POSES.size():
        _button(poses, POSES[index], select_clip.bind(ACTOR.CLIPS[index]), true)
    _section(right, "LIGHT & LOAD")
    var settings := _grid(right)
    _button(settings, "Warm light", func(): set_light(not warm), true)
    _button(settings, "Smile", _toggle_smile, true)
    _button(settings, "1 rig", _cycle_count)
    _button(settings, "Shadows", _toggle_shadows, true)
    _button(settings, "Run toggle", func(): jog = not jog, true)
    _status = Label.new()
    _status.position = Vector2(18, 0)
    _status.add_theme_font_size_override("font_size", 16)
    _status.add_theme_color_override("font_shadow_color", Color("#101f21"))
    _status.add_theme_constant_override("shadow_offset_y", 2)
    _hud.add_child(_status)
    _status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    _status.position += Vector2(17, -29)
    _hint = Label.new()
    _hint.add_theme_font_size_override("font_size", 16)
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hud.add_child(_hint)
    _hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _hint.offset_top = -56
    _hint.offset_bottom = -26

func _panel(style: StyleBoxFlat, right: bool) -> VBoxContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", style)
    _hud.add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
    panel.position += Vector2(-277 if right else 18, 18)
    if right:
        _right_panel = panel
    else:
        _left_panel = panel
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 3)
    panel.add_child(box)
    return box

func _grid(parent: VBoxContainer) -> GridContainer:
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 4)
    grid.add_theme_constant_override("v_separation", 4)
    parent.add_child(grid)
    return grid

func _label(box: VBoxContainer, text: String, size: int, color: Color) -> void:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    box.add_child(label)

func _section(box: VBoxContainer, text: String) -> void:
    _label(box, text, 13, Color("#91b7af"))

func _button(box: Container, text: String, action: Callable, toggle := false) -> void:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(122, 57)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 20)
    button.focus_mode = Control.FOCUS_NONE
    button.toggle_mode = toggle
    button.pressed.connect(action)
    box.add_child(button)
    _buttons[text] = button

func set_view(next: String) -> void:
    view = next
    _clear_touch()
    runner.position = Vector3.ZERO
    runner.velocity = Vector3.ZERO
    subject.rotation.y = 0.0
    if view == "Explore":
        yaw = PI
        selected_clip = &"Idle"
        subject.select(&"Idle")
    else:
        yaw = deg_to_rad(TURNS[turn_index])
    _stick_hud.visible = view == "Explore"
    _buttons["Run toggle"].visible = view == "Explore"
    _hint.text = "Left thumb move  •  Right thumb orbit  •  WASD + Shift" if view == "Explore" else "Drag the scene to orbit"
    for option in ["Face", "Body", "Explore"]:
        _buttons[option].set_pressed_no_signal(view == option)
    _sync_pose_controls()
    _update_camera(1.0)

func _next_angle() -> void:
    turn_index = (turn_index + 1) % TURNS.size()
    yaw = deg_to_rad(TURNS[turn_index])
    pitch = 0.20

func select_clip(clip: StringName) -> void:
    if view == "Explore":
        set_view("Body")
    selected_clip = clip
    subject.select(clip)
    _sync_pose_controls()

func _sync_pose_controls() -> void:
    _seat.visible = view != "Explore" and selected_clip in [&"SitDown", &"Seated", &"StandUp"]
    for index in POSES.size():
        _buttons[POSES[index]].set_pressed_no_signal(view != "Explore" and selected_clip == ACTOR.CLIPS[index])

func set_light(is_warm: bool) -> void:
    warm = is_warm
    _environment.background_color = Color("#273433") if not warm else Color("#282435")
    _environment.ambient_light_color = Color("#e9eff4") if not warm else Color("#c7b8d1")
    _environment.ambient_light_energy = 0.52 if not warm else 0.40
    _key.light_color = Color("#fff2df") if not warm else Color("#ffb879")
    _key.light_energy = 0.92 if not warm else 1.22
    _fill.light_color = Color("#d0e6ff") if not warm else Color("#a4aaff")
    _buttons["Warm light"].set_pressed_no_signal(warm)

func _toggle_shadows() -> void:
    shadows = not shadows
    _key.shadow_enabled = shadows

func _toggle_smile() -> void:
    subject.smile_enabled = not subject.smile_enabled

func _cycle_count() -> void:
    set_count(6 if count == 1 else (18 if count == 6 else 1))

func set_count(target: int) -> void:
    for old in copies.get_children():
        copies.remove_child(old)
        old.queue_free()
    count = target
    for index in target - 1:
        var actor := ACTOR.new()
        var column := index % 6
        var row := floori(index / 6.0)
        actor.position = Vector3((column - 2.5) * 0.85, 0, -1.45 - row * 1.0)
        copies.add_child(actor)
        actor.select(&"Idle" if index % 3 == 0 else (&"Talk" if index % 3 == 1 else &"Walk"))
    _buttons["1 rig"].text = "%d %s" % [count, "rig" if count == 1 else "rigs"]
    _update_camera(1.0)

func _physics_process(delta: float) -> void:
    if not _qa:
        if view == "Explore":
            _move(delta)
        _update_camera(minf(1.0, delta * 10.0))
    _status_timer += delta
    if _status_timer > 0.4:
        _status_timer = 0.0
        var fps := Engine.get_frames_per_second()
        var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
        var triangles := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
        _status.text = "%d FPS   %d draws   %d prims   %d rigs" % [fps, draws, triangles, count]
        if is_instance_valid(_review_callback):
            var metrics := {"fps": fps, "draws": draws, "primitives": triangles, "rigs": count,
                "view": view, "clip": subject.playback.get_current_node(),
                "x": runner.position.x, "z": runner.position.z, "yaw": yaw,
                "controls": {"Explore": _center("Explore"), "Rig count": _center("1 rig")}}
            JavaScriptBridge.get_interface("window").characterLabMetrics = JSON.stringify(metrics)

func _center(label: String) -> Array:
    var size := get_viewport().get_visible_rect().size
    var center := _buttons[label].get_global_rect().get_center() / size
    return [center.x, center.y]

func _move(delta: float) -> void:
    var keys := Vector2(
        float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
        float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
    var axis := (stick + keys).limit_length(1.0)
    if axis.length() < 0.13:
        axis = Vector2.ZERO
    var basis := Basis(Vector3.UP, yaw)
    var direction := basis * Vector3(axis.x, 0, axis.y)
    var running := jog or Input.is_physical_key_pressed(KEY_SHIFT)
    var speed := JOG_SPEED if running else WALK_SPEED
    var planar := Vector2(runner.velocity.x, runner.velocity.z).move_toward(Vector2(direction.x, direction.z) * speed, delta * 9.0)
    runner.velocity = Vector3(planar.x, -2.0, planar.y)
    runner.move_and_slide()
    runner.position.x = clampf(runner.position.x, -10, 10)
    runner.position.z = clampf(runner.position.z, -10, 10)
    if planar.length() > 0.10:
        subject.rotation.y = lerp_angle(subject.rotation.y, atan2(planar.x, planar.y), minf(1.0, delta * 11.0))
    subject.select(&"Idle" if planar.length() < 0.2 else (&"Jog" if running else &"Walk"))

func _update_camera(weight: float) -> void:
    var face := view == "Face"
    var explore := view == "Explore"
    var target := runner.position + Vector3(0, 1.39 if face else (1.06 if explore else 0.81), 0.045 if face else 0)
    var distance := 0.86 if face else (3.25 if explore else (6.1 if count > 1 else 3.30))
    camera.fov = 35 if face else (57 if explore else 37)
    var elevation := clampf(pitch - 0.11, -0.26, 0.60) if not face else clampf(pitch - 0.20, -0.45, 0.45)
    var offset := Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
    camera.position = camera.position.lerp(target + offset, weight)
    if camera.position.distance_squared_to(target) > 0.0001:
        camera.look_at(target)

func _orbit(relative: Vector2) -> void:
    yaw -= relative.x * 0.005
    pitch = clampf(pitch + relative.y * 0.004, -0.23, 0.73)

func _clear_touch() -> void:
    _left_finger = -1
    _right_finger = -1
    stick = Vector2.ZERO
    if is_instance_valid(_stick_hud):
        _stick_hud.set_stick(_stick_origin, stick, false)

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _clear_touch()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch and (not event.pressed or event.canceled):
        if event.index == _left_finger:
            _left_finger = -1
            stick = Vector2.ZERO
            _stick_hud.set_stick(_stick_origin, stick, false)
        if event.index == _right_finger:
            _right_finger = -1

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch and event.pressed and not event.canceled:
        if _left_panel.get_global_rect().has_point(event.position) or _right_panel.get_global_rect().has_point(event.position):
            return
        if view == "Explore" and event.position.x < get_viewport().get_visible_rect().size.x * 0.48:
            if _left_finger == -1:
                _left_finger = event.index
                _stick_origin = event.position
                _stick_hud.set_stick(_stick_origin, stick, true)
        elif _right_finger == -1:
            _right_finger = event.index
    elif event is InputEventScreenDrag:
        if event.index == _left_finger:
            stick = ((event.position - _stick_origin) / 66.0).limit_length()
            _stick_hud.set_stick(_stick_origin, stick, true)
        elif event.index == _right_finger:
            _orbit(event.relative)
    elif event is InputEventMouseMotion and _left_finger < 0 and _right_finger < 0:
        if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
            _orbit(event.relative)

func _samples() -> Array:
    return [
        ["face-front", "Face", 0.0, &"Idle", 0.0, false],
        ["face-three-quarter", "Face", 42.0, &"Idle", 0.0, false],
        ["face-profile", "Face", 90.0, &"Idle", 0.0, false],
        ["face-smile", "Face", 0.0, &"Idle", 0.0, true],
        ["body-front", "Body", 0.0, &"Idle", 0.0, false],
        ["body-profile", "Body", 90.0, &"Idle", 0.0, false],
        ["body-rear", "Body", 180.0, &"Idle", 0.0, false],
        ["walk", "Body", 42.0, &"Walk", 0.32, false],
        ["jog", "Body", 42.0, &"Jog", 0.24, false],
        ["seated", "Body", 40.0, &"Seated", 0.18, false],
        ["talk", "Face", 23.0, &"Talk", 0.64, false],
        ["explore", "Explore", 155.0, &"Walk", 0.22, false],
        ["six-rigs", "Body", 9.0, &"Idle", 0.0, false]
    ]

func _apply_sample(sample: Array) -> void:
    _qa = true
    set_view(sample[1])
    yaw = deg_to_rad(sample[2])
    selected_clip = sample[3]
    subject.pose(sample[3], sample[4])
    _sync_pose_controls()
    subject.smile_enabled = sample[5]
    _hud.visible = sample[0] in ["explore", "six-rigs"]
    set_light(sample[0] == "explore")
    set_count(6 if sample[0] == "six-rigs" else 1)
    _update_camera(1.0)

func _review(args: Array) -> void:
    if args.size() != 1:
        return
    if args[0] == "resume":
        _qa = false
        _hud.show()
        subject.tree.active = true
        subject.playback.start(&"Idle")
        set_view("Body")
        set_light(false)
        set_count(1)
        return
    for sample in _samples():
        if sample[0] == args[0]:
            _apply_sample(sample)
            return

func _capture(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)
    for sample in _samples():
        _apply_sample(sample)
        await get_tree().create_timer(0.36).timeout
        await RenderingServer.frame_post_draw
        var image := get_viewport().get_texture().get_image()
        image.save_png(path.path_join(sample[0] + ".png"))
    get_tree().quit()
