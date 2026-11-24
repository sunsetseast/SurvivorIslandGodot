class_name TonsaiCamp
extends Node3D

const REACH := 2.65
const CAPTURE_VIEWS := {
    "coast": [Vector3(-41, 3.25, 57), Vector3(-27, 11.0, 97)],
    "camp": [Vector3(-13, 4.1, -24), Vector3(1, 2.15, -36)],
    "fire": [Vector3(-11.0, 3.55, -28.1), Vector3(-9.0, 2.37, -31.0)],
    "shelter": [Vector3(12.0, 3.05, -28.8), Vector3(12.0, 3.0, -44.0)],
    "jungle": [Vector3(14, 2.5, -29), Vector3(26, 2.0, -10)],
    "well": [Vector3(104.1, 11.30, 33.1), Vector3(108, 10.69, 36)],
    "cave": [Vector3(4.5, 4.5, 89), Vector3(8, 8.0, 106)],
    "cave-interior": [Vector3(11, 3.4, 100), Vector3(11, 4.2, 109)],
}
var site := TonsaiSiteData.new()
var simulation := CampSimulation.new()
var terrain: TonsaiTerrain
var kit: TonsaiEnvironmentKit
var props: TonsaiCampProps
var player: CampThirdPerson
var navigation: NavigationRegion3D
var inhabitants: Array[TonsaiNpc] = []
var destinations: Dictionary[StringName, Vector3] = {}
var partner: TonsaiNpc
var hud: TonsaiCampHud
var loaded := false
var economical := false
var capture_camera: Camera3D
var _metrics_tick := 0.0
var _review := false
var _bridge: JavaScriptObject
var _capture_callback: JavaScriptObject
var _web_visibility_callback: JavaScriptObject
var _started := Time.get_ticks_msec()

func _ready() -> void:
    if not site.load_inputs():
        push_error("Tonsai inputs missing. Run bash ci/build-tonsai.sh.")
        return
    terrain = TonsaiTerrain.new()
    add_child(terrain)
    terrain.build(site)
    kit = TonsaiEnvironmentKit.new()
    add_child(kit)
    if not kit.build(site, terrain):
        push_error("Tonsai environment kit is incomplete.")
        return
    props = TonsaiCampProps.new()
    add_child(props)
    props.build(site)
    navigation = NavigationRegion3D.new()
    navigation.navigation_mesh = load(TonsaiSiteData.DIR + "navigation.res") as NavigationMesh
    if navigation.navigation_mesh == null:
        push_error("Tonsai navigation was not baked.")
        return
    add_child(navigation)
    _spawn_cast()
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = TonsaiCampHud.new()
    hud.camp = self
    layer.add_child(hud)
    if OS.has_feature("web"):
        _bridge = JavaScriptBridge.get_interface("window")
        _review = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('review')"))
        var doc := JavaScriptBridge.get_interface("document")
        _web_visibility_callback = JavaScriptBridge.create_callback(_visibility_changed)
        doc.addEventListener("visibilitychange", _web_visibility_callback)
        if _review:
            _capture_callback = JavaScriptBridge.create_callback(_capture)
            _bridge.tonsaiView = _capture_callback
    loaded = true

func _exit_tree() -> void:
    if _web_visibility_callback != null:
        JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _web_visibility_callback)

func _visibility_changed(_arguments: Array) -> void:
    hud.touch.cancel()

func _spawn_cast() -> void:
    destinations[&"fire"] = site.ground(-9.6, -33.45)
    destinations[&"shelter"] = Vector3(12.9, site.layout.shelter.deck.y, -43.3)
    destinations[&"shore"] = site.ground(-45.2, -25.3)
    destinations[&"spring"] = site.well_anchor(&"conversation")
    destinations[&"trail"] = site.ground(36.0, 4.0)
    destinations[&"work"] = site.ground(2.0, -39.6)
    player = CampThirdPerson.new()
    player.name = "Explorer"
    player.water = terrain.water
    player.water_motion = load("res://world/assets/surface-swimming.res") as AnimationLibrary
    player.position = site.point(site.layout.spawn) + Vector3.UP * .13
    add_child(player)
    var entries := [
        [&"cirie", -7.4, -25.9, &"fire", 4.8],
        [&"yul", 0.2, -30.0, &"shelter", 1.3],
        [&"parvati", -22.0, -27.8, &"shore", .2],
        [&"jeremy", 11.5, -31.0, &"spring", 2.5],
        [&"kelley", -5.0, -34.0, &"work", 3.1],
    ]
    for entry: Array in entries:
        var npc := TonsaiNpc.new()
        npc.name = entry[0]
        npc.contestant = entry[0]
        npc.position = site.ground(entry[1], entry[2]) + Vector3.UP * .14
        npc.simulation = simulation
        npc.destinations = destinations
        npc.delay = entry[4]
        npc.rotation.y = -1.4 - entry[4] * .45
        simulation.reserve_first(npc.contestant, entry[3])
        add_child(npc)
        inhabitants.append(npc)

func nearby() -> TonsaiNpc:
    if player.swimming():
        return null
    var closest: TonsaiNpc
    var distance := REACH
    for candidate in inhabitants:
        var separation := player.global_position.distance_to(candidate.global_position)
        if separation >= distance:
            continue
        var eye := Vector3.UP * 1.35
        var sight := PhysicsRayQueryParameters3D.create(player.global_position + eye, candidate.global_position + eye, 1)
        if get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
            closest = candidate
            distance = separation
    return closest

func begin_talk() -> bool:
    if is_instance_valid(partner):
        return false
    var candidate := nearby()
    if not is_instance_valid(candidate) or not simulation.begin_conversation(candidate.contestant):
        return false
    partner = candidate
    hud.touch.cancel()
    player.locked = true
    partner.interrupt(player)
    hud.show_dialog(CampSimulation.CONTESTANTS[partner.contestant])
    return true

func respond(topic: StringName) -> String:
    if not is_instance_valid(partner):
        return ""
    player.presentation.select(&"Talk")
    var reply := simulation.respond(partner.contestant, topic)
    hud.reply.text = reply
    return reply

func end_talk() -> void:
    if not is_instance_valid(partner):
        return
    simulation.end_conversation(partner.contestant)
    partner.resume()
    partner = null
    player.locked = false
    player.presentation.select(&"Idle")
    hud.hide_dialog()

func set_economy(enabled: bool) -> void:
    economical = enabled
    kit.economy(enabled)
    props.campfire.quality = CampFire.Quality.ECONOMY if enabled else CampFire.Quality.FULL

func _physics_process(delta: float) -> void:
    if is_instance_valid(partner):
        player.face_point(partner.global_position, delta)

func _process(delta: float) -> void:
    if not loaded:
        return
    _metrics_tick += delta
    if _metrics_tick < .35:
        return
    _metrics_tick = 0.0
    hud.refresh()
    var fps := Engine.get_frames_per_second()
    var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
    var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
    hud.stats.text = "%d FPS   %d draws   %dk tris   6 rigs" % [fps, draws, primitives / 1000]
    for npc in inhabitants:
        # Distant actors keep their physical schedules. Only skeletal
        # evaluation sleeps when nobody can read the pose.
        var distance := npc.global_position.distance_squared_to(player.global_position)
        npc.presentation.tree.active = distance < (38.0 if economical else 61.0) ** 2
    if _review:
        var actual := player.get_real_velocity()
        _bridge.tonsaiMetrics = JSON.stringify({
            "fps": fps, "draws": draws, "primitives": primitives, "actors": inhabitants.size() + 1,
            "x": player.position.x, "y": player.position.y, "z": player.position.z, "yaw": player.yaw,
            "travel": player.travel_distance, "arrivals": simulation.arrivals,
            "clip": player.motion_clip, "pose": player.presentation.playback.get_current_node(),
            "locomotion": CampHumanoidMotor.Locomotion.keys()[player.locomotion],
            "heading": player.travel_heading, "camera_y": player.camera.global_position.y,
            "velocity_x": actual.x, "velocity_z": actual.z,
            "intent_x": player.movement_intent.x, "intent_z": player.movement_intent.z,
            "move_finger": hud.touch.move_finger, "look_finger": hud.touch.look_finger,
            "dive_requested": player.dive_requested, "sky": TonsaiTerrain.SkyPreset.keys()[terrain.sky_preset],
            "startup_ms": Time.get_ticks_msec() - _started if not bool(_bridge.tonsaiMetrics) else 0,
            "nearby": str(hud.nearby_actor),
            "dialogue": str(partner.contestant) if is_instance_valid(partner) else "",
            "reply": hud.reply.text, "controls": hud.control_positions()
        })

func _capture(values: Array) -> void:
    if values.is_empty():
        return
    var view := String(values[0])
    if view == "shore-start":
        hud.touch.cancel()
        player.planar = Vector3.ZERO
        player.velocity = Vector3.ZERO
        player.position = site.ground(-54.0, -27.0) + Vector3.UP * .12
        player.yaw = PI * .5
        player.pitch = -.17
        player.camera.current = true
        return
    if view == "follow":
        player.camera.current = true
        return
    if not CAPTURE_VIEWS.has(view):
        return
    if capture_camera == null:
        capture_camera = Camera3D.new()
        capture_camera.far = 270
        capture_camera.fov = 65.0
        add_child(capture_camera)
    capture_camera.position = CAPTURE_VIEWS[view][0]
    capture_camera.look_at(CAPTURE_VIEWS[view][1])
    capture_camera.current = true
