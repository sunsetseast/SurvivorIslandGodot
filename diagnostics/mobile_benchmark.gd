extends Node3D
## Developer-only, no GameApp identity, saves, cloud or multiplayer services.
const ACTOR := preload("res://character_lab/actor.gd")
var actors: Array[Node3D] = []
var scene_root: Node3D
var camera: Camera3D
var sim: LocalGameSession
var count := 6
var economy := false
var tonsai := false
var sustained := false
var elapsed := 0.0
var measuring := false
var samples := PackedFloat64Array()
var sample_count := 0
var monitor_elapsed := 0.0
var draws := 0.0
var primitives := 0.0
var monitor_count := 0
var step_usec := 0
var load_usec := 0
var unload_usec := 0
var panel: VBoxContainer
var status: Label
var report: TextEdit
var count_button: Button
var quality_button: Button
var scene_button: Button
var copy_button: Button
var stress_button: Button
var _visibility: JavaScriptObject

func _ready() -> void:
    var guest := GameStateData.new_id()
    sim = LocalGameSession.new(SeasonSimulation.new(guest, GameStateData.new_id(), 7216), guest)
    # Fixed upper bound: no per-frame sample array growth.
    samples.resize(120000)
    var layer := CanvasLayer.new()
    add_child(layer)
    panel = VBoxContainer.new()
    layer.add_child(panel)
    var row := HBoxContainer.new()
    panel.add_child(row)
    count_button = _button(row, "6 rigs", _count)
    quality_button = _button(row, "Full", _quality)
    scene_button = _button(row, "Isolated", _scene)
    stress_button = _button(row, "20 seconds", _stress)
    _button(row, "Start", _start)
    _button(row, "Exit", _exit_benchmark)
    status = Label.new()
    panel.add_child(status)
    report = TextEdit.new()
    report.custom_minimum_size = Vector2(650, 150)
    report.editable = false
    report.visible = false
    panel.add_child(report)
    copy_button = _button(panel, "Copy report", _copy)
    copy_button.visible = false
    get_viewport().size_changed.connect(_layout)
    _layout()
    if OS.has_feature("web"):
        _visibility = JavaScriptBridge.create_callback(_page_visibility)
        JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _visibility)
    _rebuild()

func _button(parent: Node, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size.y = 44
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _layout() -> void:
    var size := get_viewport().get_visible_rect().size
    var window := Vector2(DisplayServer.window_get_size()).max(Vector2.ONE)
    var area := Rect2(DisplayServer.get_display_safe_area())
    if not area.has_area():
        area = Rect2(Vector2.ZERO, window)
    panel.position = area.position * size / window + Vector2(16, 12)
    var css_width := window.x
    if OS.has_feature("web"):
        css_width = float(JavaScriptBridge.get_interface("window").innerWidth)
    var content_scale := size.x / maxf(1.0, css_width)
    panel.scale = Vector2.ONE * content_scale * minf(1.0, (css_width - 32) / 720.0)

func _count() -> void:
    count = {1: 6, 6: 12, 12: 18, 18: 1}[count]
    count_button.text = "%d rigs" % count
    _rebuild()

func _quality() -> void:
    economy = not economy
    quality_button.text = "Economy" if economy else "Full"
    _rebuild()

func _scene() -> void:
    tonsai = not tonsai
    scene_button.text = "Tonsai" if tonsai else "Isolated"
    _rebuild()

func _stress() -> void:
    sustained = not sustained
    stress_button.text = "180 seconds" if sustained else "20 seconds"

func _rebuild() -> void:
    measuring = false
    report.visible = false
    copy_button.visible = false
    var started := Time.get_ticks_usec()
    if scene_root != null:
        remove_child(scene_root)
        scene_root.free()
    actors.clear()
    unload_usec = Time.get_ticks_usec() - started
    started = Time.get_ticks_usec()
    scene_root = Node3D.new()
    add_child(scene_root)
    var center := Vector3.ZERO
    if tonsai:
        var site := TonsaiSiteData.new()
        if not site.load_inputs():
            status.text = "Tonsai resources unavailable"
            return
        var terrain := TonsaiTerrain.new()
        scene_root.add_child(terrain)
        terrain.build(site)
        var kit := TonsaiEnvironmentKit.new()
        scene_root.add_child(kit)
        kit.build(site, terrain)
        kit.economy(economy)
        var props := TonsaiCampProps.new()
        scene_root.add_child(props)
        props.build(site)
        props.campfire.quality = CampFire.Quality.ECONOMY if economy else CampFire.Quality.FULL
        center = site.ground(-13, -25)
    else:
        var light := DirectionalLight3D.new()
        light.rotation_degrees = Vector3(-45, -30, 0)
        scene_root.add_child(light)
        var ground := MeshInstance3D.new()
        var plane := PlaneMesh.new()
        plane.size = Vector2(100, 100)
        ground.mesh = plane
        scene_root.add_child(ground)
    for index in count:
        var actor := ACTOR.new()
        scene_root.add_child(actor)
        actor.position = center + Vector3((index % 6 - 2.5) * 1.6, .15, (index / 6) * 2.0)
        actor.select(&"Walk" if index % 2 == 0 else &"Idle")
        actors.append(actor)
    camera = Camera3D.new()
    scene_root.add_child(camera)
    camera.position = center + Vector3(0, 5, 14)
    camera.look_at(center + Vector3(0, 1, 1))
    camera.current = true
    load_usec = Time.get_ticks_usec() - started
    status.text = "Ready · 18 simulated contestants · fixed camera · idle/walk split"

func _start() -> void:
    report.visible = false
    copy_button.visible = false
    elapsed = 0.0
    sample_count = 0
    monitor_elapsed = 0.0
    monitor_count = 0
    draws = 0.0
    primitives = 0.0
    measuring = true

func _physics_process(delta: float) -> void:
    sim.step(delta)
    step_usec = sim.last_step_usec

func _process(delta: float) -> void:
    if not measuring:
        return
    elapsed += delta
    if elapsed <= 3.0:
        status.text = "Warm-up %.1f / 3 seconds" % elapsed
        return
    var duration := 180.0 if sustained else 20.0
    if sample_count < samples.size():
        samples[sample_count] = delta * 1000.0
        sample_count += 1
    monitor_elapsed += delta
    if monitor_elapsed >= .5:
        monitor_elapsed = 0.0
        draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
        primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
        monitor_count += 1
        status.text = "Sampling %.1f / %.0fs · %d FPS · %d rigs" % [elapsed - 3, duration, Engine.get_frames_per_second(), count]
    if elapsed - 3.0 >= duration or sample_count == samples.size():
        measuring = false
        _finish()

func _finish() -> void:
    var sorted := samples.slice(0, sample_count)
    sorted.sort()
    var total := 0.0
    var slow := 0
    for value in sorted:
        total += value
        if value > 33.34:
            slow += 1
    var device := OS.get_name()
    var dpr: Variant = "unavailable"
    if OS.has_feature("web"):
        device = str(JavaScriptBridge.get_interface("navigator").userAgent)
        dpr = JavaScriptBridge.get_interface("window").devicePixelRatio
    var static_bytes := Performance.get_monitor(Performance.MEMORY_STATIC)
    var result := {
        "build_sha": ProjectSettings.get_setting("survivor_diagnostics/build_sha", "unrecorded"),
        "device_browser": device, "viewport": str(get_viewport().get_visible_rect().size),
        "device_pixel_ratio": dpr, "renderer": RenderingServer.get_current_rendering_method(),
        "quality": "Economy" if economy else "Full", "environment": "Tonsai" if tonsai else "isolated",
        "visible_rigs": count, "simulated_contestants": 18, "warmup_seconds": 3,
        "sampling_seconds": total / 1000.0, "frames": sample_count,
        "average_fps": sample_count * 1000.0 / total,
        "median_ms": (sorted[(sample_count - 1) / 2] + sorted[sample_count / 2]) * .5, "p95_ms": sorted[mini(sample_count - 1, ceili(sample_count * .95) - 1)],
        "slow_frame_percent_over_33_34ms": slow * 100.0 / sample_count,
        "draw_calls_sample_mean": draws / maxi(1, monitor_count),
        "primitives_sample_mean": primitives / maxi(1, monitor_count),
        "static_memory_bytes": static_bytes if static_bytes > 0 else "unavailable: release template",
        "render_texture_memory_estimate_bytes": _render_memory(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
        "render_buffer_memory_estimate_bytes": _render_memory(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
        "render_total_memory_estimate_bytes": _render_memory(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
        "animation_cost": "unavailable: no per-rig engine timing monitor",
        "last_simulation_step_usec": step_usec, "scene_load_usec": load_usec,
        "scene_unload_usec": unload_usec, "save_checkpoint_usec": "unavailable: benchmark never writes saves"
    }
    report.text = JSON.stringify(result, "  ")
    report.visible = true
    copy_button.visible = true
    status.text = "Complete · copy report · automated desktop results are not iPhone certification"

func _copy() -> void:
    DisplayServer.clipboard_set(report.text)
    report.select_all()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED:
        measuring = false
        set_physics_process(false)
    elif what == NOTIFICATION_APPLICATION_RESUMED:
        set_physics_process(true)


func _exit_benchmark() -> void:
    if OS.has_feature("web"):
        JavaScriptBridge.eval("const u=new URL(location.href);u.searchParams.delete('benchmark');location.href=u.href")
    else:
        get_tree().reload_current_scene()

func _page_visibility(_args: Array) -> void:
    var hidden := bool(JavaScriptBridge.get_interface("document").hidden)
    measuring = false
    set_physics_process(not hidden)
    status.text = "Interrupted · restart sampling after returning"

func _exit_tree() -> void:
    if _visibility != null:
        JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _visibility)


func _render_memory(monitor: RenderingServer.RenderingInfo) -> Variant:
    var bytes := RenderingServer.get_rendering_info(monitor)
    return bytes if bytes > 0 else "unavailable: backend did not report an estimate"
