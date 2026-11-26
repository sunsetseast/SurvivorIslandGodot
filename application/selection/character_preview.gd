class_name SurvivorCharacterPreview
extends Control
## Self-contained preview. The caller supplies the selected, authorized private
## model_path; no model is inferred, downloaded, or substituted for that entry.

const BACKGROUND := Color("#24231f")
const DRAG_RADIANS := TAU

var status_text: String:
    get:
        return _status

var _status: String = "Preview unavailable"
var _generation: int = 0
var _pending: bool = false
var _model_path: String = ""
var _portrait_path: String = ""
var _ui: Control
var _surface: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _pivot: Node3D
var _portrait: TextureRect
var _label: Label
var _radius: float = 1.0
var _mouse_drag: bool = false
var _touch_index: int = -1


func _enter_tree() -> void:
    if is_node_ready():
        _prepare()


func _ready() -> void:
    _prepare()


func _prepare() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true
    if not resized.is_connected(_frame_model):
        resized.connect(_frame_model)
    _ensure_ui()
    if _pending:
        _load_selection.call_deferred(_generation, _model_path, _portrait_path)


func show_contestant(entry: Dictionary) -> void:
    _generation += 1
    _ensure_ui()
    # Free synchronously: the next private model never overlaps the previous one.
    _dispose_model()
    _portrait.texture = null
    _portrait.hide()
    _model_path = _entry_path(entry, "model_path")
    _portrait_path = _entry_path(entry, "portrait_path")
    _pending = true
    _set_status("Loading preview…")
    _load_selection.call_deferred(_generation, _model_path, _portrait_path)


func teardown() -> void:
    _generation += 1
    _pending = false
    _model_path = ""
    _portrait_path = ""
    _dispose_model()
    if is_instance_valid(_ui):
        _ui.free()
    _ui = null
    _surface = null
    _viewport = null
    _world = null
    _camera = null
    _portrait = null
    _label = null
    _status = ""


func _exit_tree() -> void:
    teardown()


func _entry_path(entry: Dictionary, key: String) -> String:
    var value: Variant = entry.get(key, "")
    if value is String or value is StringName:
        var path := String(value).strip_edges()
        # Resource paths only; never resolve remote URLs or filesystem fallbacks.
        if path.begins_with("res://") or path.begins_with("user://"):
            return path
    return ""


func _ensure_ui() -> void:
    if is_instance_valid(_ui):
        return
    _ui = Control.new()
    _ui.name = "PreviewContent"
    _ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_ui)
    _ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var background := ColorRect.new()
    background.color = BACKGROUND
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui.add_child(background)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _surface = SubViewportContainer.new()
    _surface.name = "ModelSurface"
    _surface.stretch = true
    _surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui.add_child(_surface)
    _surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _viewport = SubViewport.new()
    _viewport.name = "ModelViewport"
    _viewport.own_world_3d = true
    _viewport.gui_disable_input = true
    _viewport.physics_object_picking = false
    _surface.add_child(_viewport)
    _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    _viewport.size_changed.connect(_frame_model)
    _world = Node3D.new()
    _world.name = "PreviewWorld"
    _viewport.add_child(_world)
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = BACKGROUND
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#c7d5ce")
    environment.ambient_light_energy = 0.65
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    _world.add_child(world_environment)
    _camera = Camera3D.new()
    _camera.fov = 34.0
    _camera.keep_aspect = Camera3D.KEEP_HEIGHT
    _world.add_child(_camera)
    _camera.current = true
    _add_light(Vector3(-35.0, -30.0, 0.0), Color("#fff0d8"), 1.2)
    _add_light(Vector3(-15.0, 135.0, 0.0), Color("#bad7ce"), 0.65)
    _portrait = TextureRect.new()
    _portrait.name = "Portrait"
    _portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui.add_child(_portrait)
    _portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _portrait.hide()
    _label = Label.new()
    _label.name = "PreviewStatus"
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _label.add_theme_color_override("font_color", Color("#e3e5dc"))
    _ui.add_child(_label)
    _label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _set_status(_status)
    _surface.hide()
    set_process_input(false)


func _add_light(rotation_degrees_value: Vector3, color: Color, energy: float) -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = rotation_degrees_value
    light.light_color = color
    light.light_energy = energy
    light.shadow_enabled = false
    _world.add_child(light)


func _load_selection(token: int, model_path: String, portrait_path: String) -> void:
    if token != _generation or not _pending or not is_inside_tree():
        return
    _pending = false
    # Loading is synchronous on the main thread, deferred to coalesce switches.
    if not model_path.is_empty() and ResourceLoader.exists(model_path, "PackedScene"):
        var scene := ResourceLoader.load(model_path, "PackedScene") as PackedScene
        if token != _generation:
            return
        if scene != null:
            var instance: Node = scene.instantiate()
            if token != _generation:
                if instance != null:
                    instance.free()
                return
            if instance is Node3D:
                _pivot = Node3D.new()
                _pivot.name = "SelectedModel"
                _world.add_child(_pivot)
                _pivot.add_child(instance)
                if token != _generation or not is_instance_valid(_pivot):
                    return
                _start_idle(instance, token)
                var bounds := _model_bounds(instance)
                if bounds.size.length_squared() > 0.000001:
                    _radius = maxf(bounds.size.length() * 0.5, 0.01)
                    # Center all nested/root transforms around the drag pivot.
                    instance.position -= bounds.get_center()
                    _frame_model()
                    _surface.show()
                    _viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
                    _set_status("")
                    return
                _dispose_model()
            elif instance != null:
                instance.free()
    if token != _generation:
        return
    if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path, "Texture2D"):
        var texture := ResourceLoader.load(portrait_path, "Texture2D") as Texture2D
        if token != _generation:
            return
        if texture != null:
            _portrait.texture = texture
            _portrait.show()
            _label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
            _set_status("3D preview unavailable")
            return
    _set_status("Preview unavailable")


func _model_bounds(model: Node3D) -> AABB:
    var bounds := AABB()
    var found: bool = false
    var nodes: Array[Node] = [model]
    var inverse: Transform3D = _pivot.global_transform.affine_inverse()
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        nodes.append_array(node.get_children())
        if node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
                continue
            var box: AABB = (inverse * mesh_instance.global_transform) * mesh_instance.get_aabb()
            if not box.position.is_finite() or not box.size.is_finite():
                continue
            bounds = bounds.merge(box) if found else box
            found = true
    return bounds


func _frame_model() -> void:
    if not is_instance_valid(_pivot) or not is_instance_valid(_camera):
        return
    # A bounding sphere remains framed at every yaw, including narrow layouts.
    var aspect: float = maxf(size.x, 1.0) / maxf(size.y, 1.0)
    var half_vertical: float = deg_to_rad(_camera.fov * 0.5)
    var half_horizontal: float = atan(tan(half_vertical) * aspect)
    var distance: float = _radius * 1.1 / sin(minf(half_vertical, half_horizontal))
    _camera.position = Vector3(0.0, 0.0, distance)
    _camera.near = maxf(0.001, distance - _radius * 1.5)
    _camera.far = distance + _radius * 3.0


func _start_idle(model: Node3D, token: int) -> void:
    for node: Node in model.find_children("*", "AnimationTree", true, false):
        (node as AnimationTree).active = false
    for node: Node in model.find_children("*", "Camera3D", true, false):
        (node as Camera3D).current = false
    _camera.current = true
    for node: Node in model.find_children("*", "AnimationPlayer", true, false):
        var player := node as AnimationPlayer
        player.stop()
        for clip: StringName in player.get_animation_list():
            var leaf: String = String(clip).get_slice("/", String(clip).get_slice_count("/") - 1)
            leaf = leaf.get_slice("|", leaf.get_slice_count("|") - 1).to_lower()
            if leaf == "idle" or leaf.begins_with("idle_") or leaf == "idleloop":
                player.animation_finished.connect(_repeat_idle.bind(player, token))
                player.play(clip)
                player.advance(0.0)
                break


func _repeat_idle(clip: StringName, player: AnimationPlayer, token: int) -> void:
    if token == _generation and is_instance_valid(player):
        player.play(clip)


func _dispose_model() -> void:
    _reset_drag()
    if is_instance_valid(_viewport):
        _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    if is_instance_valid(_surface):
        _surface.hide()
    if is_instance_valid(_pivot):
        _pivot.free()
    _pivot = null


func _set_status(value: String) -> void:
    _status = value
    if is_instance_valid(_label):
        _label.text = value
        _label.visible = not value.is_empty()
        if not is_instance_valid(_portrait.texture):
            _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _gui_input(event: InputEvent) -> void:
    if not is_instance_valid(_pivot):
        return
    if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and _touch_index < 0:
            _mouse_drag = true
            set_process_input(true)
            accept_event()
    elif event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed and _touch_index < 0 and not _mouse_drag:
            _touch_index = touch.index
            set_process_input(true)
            accept_event()


func _input(event: InputEvent) -> void:
    if not is_instance_valid(_pivot) or not is_visible_in_tree():
        _reset_drag()
        return
    var handled: bool = false
    if _mouse_drag and event is InputEventMouseMotion:
        _rotate_model((event as InputEventMouseMotion).relative.x)
        handled = true
    elif _mouse_drag and event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
            _reset_drag()
            handled = true
    elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
        _rotate_model((event as InputEventScreenDrag).relative.x)
        handled = true
    elif event is InputEventScreenTouch and (event as InputEventScreenTouch).index == _touch_index:
        if not (event as InputEventScreenTouch).pressed:
            _reset_drag()
            handled = true
    if handled:
        get_viewport().set_input_as_handled()


func _rotate_model(horizontal: float) -> void:
    _pivot.rotation.y = wrapf(_pivot.rotation.y + horizontal / maxf(size.x, 1.0) * DRAG_RADIANS, -PI, PI)


func _reset_drag() -> void:
    _mouse_drag = false
    _touch_index = -1
    set_process_input(false)


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
        _reset_drag()
