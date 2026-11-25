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
const LOCATION := "tonsai"
var session: GameSession
var local_host: LocalGameSession
var remote: RemoteGameSession
var profile: PlayerProfile
var _standalone := false
signal preference_failed
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
var _tracing := false
var _trace: Array = []
var _territory := PackedVector2Array()

func _ready() -> void:
    # Only the B player opts in. The camp, NPCs and baseline keep their timing.
    get_tree().physics_interpolation = true
    physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
    if session == null:
        _standalone = true
        var guest := GameStateData.new_id()
        session = LocalGameSession.new(SeasonSimulation.new(guest, GameStateData.new_id(), 7216), guest)
    local_host = session as LocalGameSession
    remote = session as RemoteGameSession
    if local_host != null:
        local_host.bind_physical_location(LOCATION)
    session.resolved.connect(_apply_talk_result)
    _spawn_cast()
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = TonsaiCampHud.new()
    hud.camp = self
    layer.add_child(hud)
    if profile != null:
        hud.apply_preferences()
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
    if session != null and session.resolved.is_connected(_apply_talk_result):
        session.resolved.disconnect(_apply_talk_result)
    if _bridge != null and _review:
        _bridge.tonsaiView = null
        _bridge.tonsaiMetrics = null
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
    for record: Dictionary in site.layout.territory:
        _territory.append(Vector2(TonsaiTerrain.OFFSHORE_EDGE if record.x == -70 else float(record.x), record.z))
    player = CampThirdPerson.new()
    player.name = "Explorer"
    player.water = terrain.water
    player.water_motion = load("res://world/assets/surface-swimming.res") as AnimationLibrary
    player.position = site.point(site.layout.spawn) + Vector3.UP * .13
    add_child(player)
    player.process_priority = -1
    player.select_controller(true)
    var view := session.view(LOCATION)
    if remote != null:
        var initial := remote.movement(view.controlled)
        player.remote = remote
        player.remote_actor = view.controlled
        player.position = SurvivorMultiplayerWire.position_from(initial)
        player.set_heading(initial[3])
        player.locomotion = int(initial[4])
        player.restore_dive(initial[5])
        player.collision_mask = 1 | 4
        player.sync_camera()
    else:
        _restore_pose(view.pose)
    props.campfire.lit = view.objects.fire.lit
    # Initial formation is presentation data. The assigned camp roster comes from the session.
    var entries := [
        Vector3(-7.4, 4.8, -25.9), Vector3(.2, 1.3, -30), Vector3(-22, .2, -27.8),
        Vector3(11.5, 2.5, -31), Vector3(-5, 3.1, -34),
    ]
    for id: String in view.cast:
        if id == view.controlled:
            continue
        var entry: Vector3 = entries[inhabitants.size() % entries.size()]
        var npc := TonsaiNpc.new()
        npc.name = id
        npc.contestant = id
        npc.display_name = view.cast[id].name
        npc.position = site.ground(entry.x, entry.z) + Vector3.UP * .14
        npc.session = session
        npc.local_host = local_host
        npc.remote = remote
        if remote != null:
            var row := remote.movement(id)
            npc.position = SurvivorMultiplayerWire.position_from(row)
            for member: Dictionary in remote.room.roster:
                if member.contestant == id:
                    npc.is_remote_human = true
        npc.destinations = destinations
        npc.delay = entry.y if view.tick == 0 else .2
        npc.rotation.y = -1.4 - entry.y * .45
        var activity: Dictionary = view.cast[id]
        if remote == null and activity.stage == "occupied":
            npc.position = destinations[StringName(activity.activity)] + Vector3.UP * .14
        add_child(npc)
        inhabitants.append(npc)

func checkpoint_player() -> bool:
    var point := player.position
    if not _valid_point(point):
        return false
    return local_host != null and local_host.checkpoint_pose({"location": LOCATION, "position": [point.x, point.y, point.z],
        "heading": wrapf(player.travel_heading, -PI, PI), "yaw": wrapf(player.yaw, -PI, PI),
        "pitch": player.pitch, "underwater": player.underwater() and player.dive_requested})

func _restore_pose(pose: Dictionary) -> void:
    if not GameStateData.pose(pose):
        return
    var point := Vector3(pose.position[0], pose.position[1], pose.position[2])
    if not _valid_point(point):
        return
    # Spawn with clearance; the existing motor reacquires floor/water on its first tick.
    player.position = point + Vector3.UP * .06
    player.yaw = pose.yaw
    player.pitch = pose.pitch
    player.set_heading(pose.heading)
    player.restore_dive(pose.underwater)
    player.sync_camera()

func _valid_point(point: Vector3) -> bool:
    return Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), _territory) \
        and point.y >= site.height(point.x, point.z) - .35

func _talk_action(kind: String, target: String, topic := "") -> Dictionary:
    return session.submit({"id": GameStateData.new_id(), "actor": SeasonCatalog.CONTROLLED,
        "kind": kind, "target": target, "topic": topic})

func remember_preference(key: String, value: Variant) -> void:
    if profile != null and not profile.set_preference(key, value):
        preference_failed.emit()

func nearby() -> TonsaiNpc:
    if player.swimming() or (remote != null and not remote.active):
        return null
    var closest: TonsaiNpc
    var distance := REACH
    for candidate in inhabitants:
        if candidate.is_remote_human:
            continue
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
    if not is_instance_valid(candidate):
        return false
    if local_host != null:
        local_host.observe_talk(candidate.contestant, player.position.distance_to(candidate.position), true)
    return _talk_action("talk.begin", candidate.contestant).get("ok", false)

func respond(topic: StringName) -> String:
    if not is_instance_valid(partner):
        return ""
    var result := _talk_action("talk.respond", partner.contestant, String(topic))
    return result.get("event", {}).get("reply", "")

func end_talk() -> void:
    if is_instance_valid(partner):
        _talk_action("talk.end", partner.contestant)

func _apply_talk_result(result: Dictionary) -> void:
    if not result.get("ok", false):
        return
    var event: Dictionary = result.event
    match event.type:
        "conversation_opened":
            for npc in inhabitants:
                if npc.contestant == event.with:
                    partner = npc
                    hud.touch.cancel()
                    player.locked = true
                    partner.interrupt(player)
                    if remote != null:
                        partner.talking_to = null
                    hud.show_dialog(partner.display_name)
                    break
        "conversation_reply":
            player.presentation.select(&"Talk")
            hud.reply.text = event.reply
        "conversation_closed":
            if is_instance_valid(partner):
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
    if not loaded:
        return
    if _standalone:
        local_host.step(delta)
    if is_instance_valid(partner) and (remote == null or remote.active):
        player.face_point(partner.global_position, delta)

func _process(delta: float) -> void:
    if not loaded:
        return
    hud.touch.trace.frame(player)
    if _tracing and _trace.size() < 1200:
        var angles := player.camera.global_basis.get_euler()
        var velocity := player.get_real_velocity()
        var point := player.position
        var view := player.camera.global_position
        _trace.append([delta, player.yaw, player.pitch, angles.y, angles.x,
            point.x, point.y, point.z, velocity.x, velocity.z, player.travel_heading,
            player.camera.position.z, player.camera_obstructed(), player.raw_look.x,
            player.raw_look.y, view.x, view.y, view.z, hud.touch.move_finger,
            hud.touch.look_finger, player.movement_intent.x, player.movement_intent.z, Time.get_ticks_usec()])
    _metrics_tick += delta
    if _metrics_tick < .35:
        return
    _metrics_tick = 0.0
    hud.refresh()
    hud.refresh_diagnostics(delta)
    var fps := Engine.get_frames_per_second()
    var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
    var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
    var day: int = local_host.current_day() if local_host != null else int(session.view(LOCATION).get("day", 1))
    hud.stats.text = "Day %d   ·   %d FPS   ·   %d rigs" % [day, fps, inhabitants.size() + 1]
    for npc in inhabitants:
        # Distant actors keep their physical schedules. Only skeletal
        # evaluation sleeps when nobody can read the pose.
        var distance := npc.global_position.distance_squared_to(player.global_position)
        npc.presentation.tree.active = distance < (38.0 if economical else 61.0) ** 2
    if _review:
        var actual := player.get_real_velocity()
        var remote_peer := []
        for npc in inhabitants:
            if npc.is_remote_human:
                remote_peer = [npc.position.x, npc.position.y, npc.position.z]
                break
        _bridge.tonsaiMetrics = JSON.stringify({
            "build": CampTouch.TouchTrace.BUILD,
            "fps": fps, "draws": draws, "primitives": primitives, "actors": inhabitants.size() + 1,
            "remote_peer": remote_peer,
            "x": player.position.x, "y": player.position.y, "z": player.position.z, "yaw": player.yaw,
            "travel": player.travel_distance, "arrivals": local_host.arrivals(LOCATION) if local_host != null else 0,
            "clip": player.motion_clip, "pose": player.presentation.playback.get_current_node(),
            "locomotion": CampHumanoidMotor.Locomotion.keys()[player.locomotion],
            "heading": player.travel_heading, "camera_y": player.camera.global_position.y,
            "controller": "B" if player.controller_b else "A",
            "economy": economical,
            "view_yaw": player.rendered_yaw(), "view_pitch": player.camera.global_basis.get_euler().x,
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
    if view == "trace-start":
        _trace.clear()
        _tracing = true
        return
    if view == "trace-stop":
        _tracing = false
        _bridge.tonsaiTrace = JSON.stringify(_trace)
        return
    if view == "shore-start":
        hud.touch.cancel()
        player.planar = Vector3.ZERO
        player.velocity = Vector3.ZERO
        player.position = site.ground(-54.0, -27.0) + Vector3.UP * .12
        player.yaw = PI * .5
        player.pitch = -.17
        player.sync_camera()
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
