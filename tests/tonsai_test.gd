extends SceneTree

var camp: TonsaiCamp
var failures := 0

func _initialize() -> void:
    call_deferred("_test")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func _ticks(count: int) -> void:
    for i in count:
        await physics_frame

func _test() -> void:
    camp = load("res://tonsai/camp.tscn").instantiate()
    root.add_child(camp)
    await _ticks(18)
    if not camp.loaded:
        printerr("FAIL: Tonsai did not load")
        quit(1)
        return
    _check(camp.inhabitants.size() == 5, "Expected six rigs")
    _check(camp.site.layout.trails.size() == 12, "Missing trails")
    _check(camp.site.layout.hidingCandidates.size() == 39, "Missing candidate identities")
    _check(camp.kit.library.size() >= 45 and camp.kit.sections > 100, "Incomplete environment kit")
    _check(camp.player.is_on_floor(), "Spawn is not grounded")
    _check(camp.begin_talk(), "Expected nearby contestant at camp spawn")
    if is_instance_valid(camp.partner):
        var contestant := camp.partner
        var id := contestant.contestant
        var previous := contestant.position
        await _ticks(35)
        _check(contestant.position.distance_to(previous) < .12, "Talk should interrupt travel")
        _check(contestant.motion_clip == &"Talk", "NPC did not play talking state")
        _check(not camp.respond(&"water").is_empty(), "Dialogue response missing")
        _check(camp.simulation.knowledge_for(id).size() == 1, "Participant has no conversation memory")
        _check(camp.simulation.knowledge_for(&"yul").is_empty(), "Private memory leaked across identities")
        camp.end_talk()
        _check(not camp.player.locked and contestant.talking_to == null, "Controls did not resume")
        await _ticks(420)
        _check(contestant.travel_distance > 3.0, "NPC did not resume a physical route")
    # Isolate static site reachability from momentary NPC traffic. Dialogue and
    # contestant movement are exercised above and run throughout this sequence.
    camp.player.collision_mask &= ~8
    var travel_points := {
        "shelter ramp foot": camp.site.ground(12, -32.5), "shelter deck": camp.destinations[&"shelter"], "shelter exit": camp.site.ground(12, -32.5), "camp trail": camp.site.ground(-20, -27.0), "west beach": camp.site.ground(-47.0, -27.1),
        "well meeting point": camp.site.well_anchor(&"conversation"),
        "well collection point": camp.site.well_anchor(&"collection"), "quiet alcove": camp.site.ground(29, 85.5),
        "cave interior": camp.site.ground(11, 105),
    }
    for label: String in travel_points:
        await _walk_route(label, travel_points[label])
    _check(camp.simulation.arrivals >= 3, "NPCs did not arrive in sequence")
    camp.player.touch_direction = Vector2.ZERO
    camp.player.collision_mask |= 8
    await _ticks(18)
    _check(not camp.begin_talk(), "Started a conversation outside reach")
    var from := camp.site.ground(11, 105)
    var wall_target := Vector3(15.5, from.y, from.z)
    var hit := camp.get_world_3d().direct_space_state.intersect_ray(
        PhysicsRayQueryParameters3D.create(from + Vector3.UP, wall_target + Vector3.UP, 1))
    _check(not hit.is_empty(), "No physical cave wall")
    await _test_touch()
    await _test_water()
    _test_props()
    print("Tonsai result: ", camp.player.travel_distance, " m continuously walked; ",
        camp.simulation.arrivals, " NPC arrivals; ", failures, " failures")
    quit(int(failures > 0))

func _test_water() -> void:
    var player := camp.player
    player.collision_mask &= ~8
    player.global_position = camp.site.ground(-51.0, -27.0) + Vector3.UP * .10
    player.yaw = 0.0
    player.pitch = -.31
    await _ticks(12)
    player.touch_direction = Vector2.RIGHT
    await _ticks(25)
    _check(absf(angle_difference(player.travel_heading, PI * .5)) < .20, "Slow 90-degree land turn")
    player.touch_direction = Vector2.LEFT
    await _ticks(16)
    _check(absf(angle_difference(player.travel_heading, -PI * .5)) < .20, "Slow 180-degree land turn")
    player.yaw = 0.0
    player.touch_direction = Vector2.ZERO
    player.global_position = camp.site.ground(-52.0, -27.0) + Vector3.UP * .12
    await _ticks(18)
    for cycle in 2:
        player.touch_direction = Vector2.LEFT
        var waded := false
        for frame in 650:
            await physics_frame
            waded = waded or player.locomotion == CampHumanoidMotor.Locomotion.WADE
            if player.locomotion == CampHumanoidMotor.Locomotion.SWIM and player.position.x < -68:
                break
        _check(waded and player.swimming(), "Walk did not become wade then swim")
        _check(player.presentation.playback.get_current_node() == &"Swim", "Forward stroke missing")
        var bed := camp.site.height(player.position.x, player.position.z)
        _check(player.position.y > bed and absf(player.position.y - camp.terrain.water.level + CampHumanoidMotor.FLOAT_OFFSET) < .13,
            "Swimmer left the surface or intersected the bed")
        _check(player.camera.global_position.y > camp.terrain.water.level, "Swimming camera submerged")
        player.touch_direction = Vector2.ZERO
        await _ticks(85)
        _check(player.locomotion == CampHumanoidMotor.Locomotion.TREAD, "Stopped swimmer did not tread")
        _check(player.presentation.playback.get_current_node() == &"Tread", "Treading clip missing")
        var still := player.position
        await _ticks(40)
        _check(player.position.distance_to(still) < .07, "Treading did not hold position")
        if cycle == 0:
            player.touch_direction = Vector2.LEFT
            await _ticks(590)
            _check(player.position.x >= TonsaiTerrain.OFFSHORE_EDGE and player.position.x < -82.0,
                "Offshore boundary is missing or placed too close to shore")
            _check(player.swimming(), "Lost surface support at offshore limit")
            await _test_dive()
        player.touch_direction = Vector2.RIGHT
        waded = false
        for frame in 1350:
            await physics_frame
            waded = waded or player.locomotion == CampHumanoidMotor.Locomotion.WADE
            if player.position.x > -53.0 and player.is_on_floor():
                break
        _check(waded and player.locomotion == CampHumanoidMotor.Locomotion.LAND and player.is_on_floor(),
            "Swimmer could not wade and walk back onto dry land")
        player.touch_direction = Vector2.ZERO
        await _ticks(22)
    print("Two swim cycles and offshore limit exercised")

func _test_dive() -> void:
    var player := camp.player
    var level := camp.terrain.water.level
    player.touch_direction = Vector2.ZERO
    await _ticks(24)
    _check(player.can_dive(), "Dive missing in deep water")
    player.toggle_dive()
    await _ticks(110)
    _check(player.underwater() and player.position.y < level - 2.2, "Dive did not descend")
    _check(player.camera.global_position.y < level, "Camera did not cross the surface")
    var before := player.position
    player.pitch = -.59
    player.touch_direction = Vector2.UP
    await _ticks(86)
    _check(player.position.z < before.z - 1.3 and player.position.y < before.y - .5,
        "Underwater steering did not follow the camera pitch and yaw")
    _check(player.position.x >= TonsaiTerrain.OFFSHORE_EDGE, "Diver crossed the boundary")
    _check(player.position.y > camp.site.height(player.position.x, player.position.z),
        "Diver clipped into the seabed")
    player.touch_direction = Vector2.ZERO
    player.toggle_dive()
    await _ticks(165)
    _check(player.locomotion == CampHumanoidMotor.Locomotion.TREAD and player.camera.global_position.y > level,
        "Surface did not return to treading and above-water camera")
    player.pitch = -.31

func _test_touch() -> void:
    var player := camp.player
    var touch := camp.hud.touch
    player.global_position = camp.site.ground(-51.0, -25.0) + Vector3.UP * .1
    var size := root.get_visible_rect().size
    var window := DisplayServer.window_get_size()
    var short_edge := minf(window.x, window.y)
    if short_edge <= 1.0:
        short_edge = minf(size.x, size.y)
    var left := touch.home()
    var right := size * Vector2(.67, .49)
    _press(1, left)
    _drag(1, left + Vector2(0, -touch.radius), Vector2.ZERO)
    await _ticks(12)
    _press(2, right)
    var start_yaw := player.yaw
    var start_distance := player.travel_distance
    for i in 8:
        _drag(2, size * (Vector2(.41, .5) if i % 2 == 0 else Vector2(.7, .5)),
            Vector2(short_edge * .43, 0))
        await _ticks(8)
        _check(absf(angle_difference(player.yaw, start_yaw - (i + 1) * .43
            * CampThirdPerson.LOOK_RADIANS_PER_SHORT_EDGE)) < .003, "Orbit lost or repeated a swipe")
        _check(touch.look_finger == 2 and touch.move_finger == 1, "Finger crossed the touch split")
    _check(player.travel_distance > start_distance + .65, "Forward hold stopped during orbit")
    _press(2, right, false)
    _check(touch.look_finger == -1 and touch.move_finger == 1, "Look release also released movement")
    var held_yaw := player.yaw
    await _ticks(180)
    _check(is_equal_approx(held_yaw, player.yaw), "Camera recentered without a reset")
    _press(3, right)
    _press(1, left, false, true)
    _check(touch.move_finger == -1 and touch.look_finger == 3 and player.touch_direction == Vector2.ZERO,
        "Move cancellation affected the look owner")
    _drag(3, right, Vector2(short_edge * .15, 0))
    touch.cancel()
    await _ticks(2)
    _check(touch.look_finger == -1 and player.yaw == held_yaw, "Cancellation left queued look")
    player.reset_camera()
    await _ticks(2)
    _check(absf(angle_difference(player.yaw, player.travel_heading + PI)) < .001, "Camera reset failed")

func _press(index: int, where: Vector2, pressed := true, canceled := false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = where
    event.pressed = pressed
    event.canceled = canceled
    root.push_input(event, true)

func _drag(index: int, where: Vector2, screen_delta: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = where
    event.screen_relative = screen_delta
    root.push_input(event, true)

func _test_props() -> void:
    _check(is_instance_valid(camp.props.well_lid) and is_instance_valid(camp.props.well_scoop),
        "Well lid and scoop must be independently movable")
    var fire := camp.props.campfire
    _check(fire.lit and fire.is_processing(), "Campfire started extinguished")
    camp.set_economy(true)
    _check(fire.quality == CampFire.Quality.ECONOMY, "Performance preset did not reduce fire effects")
    fire.lit = false
    _check(not fire.is_processing(), "Extinguished fire still processes")
    fire.lit = true
    camp.set_economy(false)
    camp.terrain.set_sky_preset(TonsaiTerrain.SkyPreset.CLOUDY)
    _check(camp.terrain.atmosphere.sky != null, "Cloudy panorama missing")
    camp.terrain.set_sky_preset(TonsaiTerrain.SkyPreset.NIGHT)
    _check(camp.terrain.atmosphere.sky == null and camp.terrain.sun.light_energy < .2, "Night preset failed")
    camp.terrain.set_sky_preset(TonsaiTerrain.SkyPreset.CLEAR)
    _check(camp.terrain.atmosphere.sky != null, "Clear panorama was not restored")

func _walk_route(label: String, target: Vector3) -> void:
    var map := camp.navigation.get_navigation_map()
    var path := NavigationServer3D.map_get_path(map, camp.player.global_position, target, true)
    _check(path.size() > 1 and path[path.size() - 1].distance_to(target) < 1.1, "Unreachable nav target: " + label)
    if path.size() <= 1:
        return
    var start := camp.player.travel_distance
    for i in range(1, path.size()):
        var point := path[i]
        var closest := INF
        var stalled := 0
        var tolerance := .48 if i == path.size() - 1 else .16
        while _planar_distance(camp.player.global_position, point) > tolerance:
            var offset := point - camp.player.global_position
            var local := Basis(Vector3.UP, -camp.player.yaw) * Vector3(offset.x, 0, offset.z)
            camp.player.touch_direction = Vector2(local.x, local.z).limit_length()
            camp.player.run_toggled = offset.length() > 5.0
            await physics_frame
            var current := _planar_distance(camp.player.global_position, point)
            if current < closest - .04:
                stalled = 0
                closest = current
            else:
                stalled += 1
            if stalled >= 96:
                var blocker: String = str(camp.player.get_last_slide_collision().get_collider().name) if camp.player.get_slide_collision_count() else ""
                _check(false, "Route blocked at %s toward %s (%s; %s)" % [camp.player.position, point, label, blocker])
                break
        if stalled >= 96:
            break
    var final := camp.player.global_position
    _check(final.distance_to(target) < 1.5, "Stopped short of " + label)
    print("Route ", label, " walked ", snappedf(camp.player.travel_distance - start, .1), " m, arrived at ", final)

func _planar_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()
