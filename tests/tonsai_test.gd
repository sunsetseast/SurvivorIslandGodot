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
    if camp.loaded:
        camp.hud.select_controller(false)
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
    var stick := camp.hud.touch.home()
    _press(1, stick)
    _drag(1, stick - Vector2(0, camp.hud.touch.radius), Vector2.ZERO)
    await _ticks(3)
    _check(camp.begin_talk(), "Expected nearby contestant at camp spawn")
    if is_instance_valid(camp.partner):
        var contestant := camp.partner
        var id := contestant.contestant
        var previous := contestant.position
        await _ticks(35)
        _check(camp.hud.touch.move_finger == -1 and camp.player.movement_intent == Vector3.ZERO
            and camp.player.planar == Vector3.ZERO, "Conversation kept the previous movement gesture")
        _check(contestant.position.distance_to(previous) < .12, "Talk should interrupt travel")
        _check(contestant.motion_clip == &"Talk", "NPC did not play talking state")
        _check(not camp.respond(&"water").is_empty(), "Dialogue response missing")
        _check(camp.simulation.knowledge_for(id).size() == 1, "Participant has no conversation memory")
        _check(camp.simulation.knowledge_for(&"yul").is_empty(), "Private memory leaked across identities")
        camp.end_talk()
        _check(not camp.player.locked and contestant.talking_to == null, "Controls did not resume")
        _drag(1, stick - Vector2(0, camp.hud.touch.radius), Vector2.ZERO)
        await _ticks(2)
        _check(camp.player.movement_intent == Vector3.ZERO, "Old finger resumed after conversation")
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
    await _test_movement_intent()
    await _test_camera_comparison()
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
    if player.controller_b:
        var deep_y := player.position.y
        player.pitch = .52
        await _ticks(70)
        _check(player.underwater() and player.position.y > deep_y + .35,
            "Pitch-driven ascent did not preserve the underwater state")
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
    event.relative = screen_delta
    root.push_input(event, true)

func _test_camera_comparison() -> void:
    var player := camp.player
    var touch := camp.hud.touch
    var origin := Vector3(500, .05, 500)
    var left := touch.home()
    var right := root.get_visible_rect().size * Vector2(.69, .51)
    var measured_steps: Array[float] = []
    camp.hud.steering_button.pressed.emit() # Return to intent-preserving steering.
    player.water = CampWaterSurface.new(0.0, func(_x: float, _z: float) -> float: return 0.0)
    for use_b: bool in [false, true]:
        camp.hud.select_controller(use_b)
        player.position = origin
        player.velocity = Vector3.ZERO
        player.planar = Vector3.ZERO
        player.yaw = 0.0
        player.pitch = -.31
        player.set_heading(PI)
        player.sync_camera()
        await _ticks(8)
        player.run_toggled = true
        _press(1, left)
        _drag(1, left + Vector2.UP * touch.radius, Vector2.ZERO)
        await _ticks(36)
        _press(2, right)
        var window := DisplayServer.window_get_size()
        var short_edge := root.get_visible_rect().size.y if use_b else minf(window.x, window.y)
        if short_edge <= 1.0:
            short_edge = root.get_visible_rect().size.y
        var pixels := short_edge / CampThirdPerson.LOOK_RADIANS_PER_SHORT_EDGE
        var previous := player.camera.global_basis.get_euler()
        var max_step := 0.0
        var swept := 0.0
        # Batched and alternating delivery, full clockwise orbit, and vertical input.
        for frame in 56:
            if frame in [0, 4, 5, 12, 16, 21]:
                var step: float = [-1.2, .6, -1.68, -1.4, -1.4, -(TAU - 5.08)][[0, 4, 5, 12, 16, 21].find(frame)]
                _drag(2, right, Vector2(step * pixels, .35 * pixels if frame == 4 else 0.0))
            await _ticks(1)
            var angles := player.camera.global_basis.get_euler()
            var separation := angle_difference(previous.y, angles.y)
            swept += separation
            max_step = maxf(max_step, absf(separation))
            previous = angles
            var actual := player.get_real_velocity() * Vector3(1, 0, 1)
            _check(actual.normalized().dot(Vector3.FORWARD) > .995, "Camera comparison redirected held run")
        _check(absf(swept - TAU) < .03 and previous.x < -.5,
            "Camera comparison lost a full rotation or vertical drag")
        measured_steps.append(max_step)
        print("Camera ", "B" if use_b else "A", " maximum rendered step ", rad_to_deg(max_step), " deg")
        _press(2, right, false)
        _press(1, left, false)
        await _ticks(6)
    _check(measured_steps[1] < measured_steps[0] * .68, "B did not smooth batched camera updates")

    # The exact same capsule and room geometry are used for both cameras.
    var wall := StaticBody3D.new()
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(6.0, 4.0, .25)
    collision.shape = box
    wall.add_child(collision)
    wall.position = origin + Vector3(0, 1.0, 1.9)
    camp.add_child(wall)
    for use_b: bool in [false, true]:
        camp.hud.select_controller(use_b)
        player.position = origin
        player.planar = Vector3.ZERO
        player.yaw = 0.0
        player.pitch = -.31
        player.sync_camera()
        await _ticks(12)
        _check(player.camera_obstructed() and player.camera.global_position.z < wall.position.z - .15,
            "Camera crossed a wall during comparison")
    var shortened := player.camera.position.z
    wall.queue_free()
    await _ticks(5)
    _check(player.camera.position.z < shortened + .5, "B snapped outward after clearing the wall")
    await _ticks(55)
    _check(player.camera.position.z > 4.1 and not player.camera_obstructed(), "B did not recover boom distance")
    camp.hud.steering_button.pressed.emit()
    _press(1, left)
    _drag(1, left + Vector2.UP * touch.radius, Vector2.ZERO)
    await _ticks(32)
    var heading := player.travel_heading
    var before := player.position
    _press(2, right)
    var edge := root.get_visible_rect().size.y
    _drag(2, right, Vector2(edge * .95, 0))
    await _ticks(34)
    _check(absf(angle_difference(heading, player.travel_heading)) < PI / 2 and player.position.z < before.z,
        "B camera steering chased a fast glance")
    _press(2, right, false)
    var held := player.movement_intent.normalized()
    await _ticks(15)
    _check(player.movement_intent.normalized().dot(held) > .99, "B camera steering caught up after release")
    _press(2, right)
    var slow_turn_start := player.travel_heading
    for frame in 30:
        _drag(2, right, Vector2(edge * .006, 0))
        await _ticks(1)
    _check(angle_difference(slow_turn_start, player.travel_heading) < -.22,
        "B camera steering ignored a sustained slow orbit")
    var switch_position := player.position
    camp.hud.select_controller(false)
    _check(player.position == switch_position and touch.move_finger == -1 and touch.look_finger == -1,
        "Controller swap moved the player or kept old touches")
    camp.hud.select_controller(true)
    camp.hud.steering_button.pressed.emit()
    player.run_toggled = false
    player.planar = Vector3.ZERO
    player.velocity = Vector3.ZERO
    player.water = camp.terrain.water
    await _test_water()
    await _test_cave_orbit()

func _test_cave_orbit() -> void:
    var player := camp.player
    var right := root.get_visible_rect().size * Vector2(.70, .51)
    for use_b: bool in [false, true]:
        camp.hud.select_controller(use_b)
        player.position = camp.site.ground(11, 105) + Vector3.UP * .06
        player.velocity = Vector3.ZERO
        player.planar = Vector3.ZERO
        player.yaw = 0.0
        player.pitch = -.08
        player.sync_camera()
        await _ticks(10)
        _press(2, right)
        var edge := root.get_visible_rect().size.y
        if not use_b:
            var window := DisplayServer.window_get_size()
            if minf(window.x, window.y) > 1.0:
                edge = minf(window.x, window.y)
        var blocked := false
        for step in 44:
            _drag(2, right, Vector2(edge * .054, 0))
            await _ticks(2)
            blocked = blocked or player.camera_obstructed()
            var ray := PhysicsRayQueryParameters3D.create(player.pivot.global_position,
                player.camera.global_position, 1)
            _check(player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),
                "Cave orbit placed the camera behind geometry")
        _check(blocked, "Cave orbit did not exercise an obstruction")
        _press(2, right, false)

func _test_movement_intent() -> void:
    var player := camp.player
    var touch := camp.hud.touch
    # A flat pad isolates steering from slope, obstacle and wave effects.
    var pad_origin := Vector3(500, 0, 500)
    var pad := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(80, 1, 80)
    shape.shape = box
    pad.add_child(shape)
    pad.position = pad_origin - Vector3.UP * .5
    camp.add_child(pad)
    var left := touch.home()
    var size := root.get_visible_rect().size
    var right := size * Vector2(.67, .49)
    var window := DisplayServer.window_get_size()
    var short_edge := minf(window.x, window.y)
    if short_edge <= 1.0:
        short_edge = minf(size.x, size.y)
    var pixels_per_radian := short_edge / CampThirdPerson.LOOK_RADIANS_PER_SHORT_EDGE
    var forward := Vector2.UP * touch.radius
    for depth in [0.0, .6, 6.0]:
        player.water = CampWaterSurface.new(depth, func(_x: float, _z: float) -> float: return 0.0)
        var angles := [45, -45, 90, -90, 180, -180, 360, -360] if depth == 0.0 else [360, -360]
        for degrees in angles:
            touch.cancel()
            player.position = pad_origin + Vector3.UP * (depth - 1.07 if depth > 1.0 else .04)
            player.velocity = Vector3.ZERO
            player.planar = Vector3.ZERO
            player.yaw = .37
            player.set_heading(PI + player.yaw)
            await _ticks(10)
            player.run_toggled = true
            _press(1, left)
            _drag(1, left + forward, Vector2.ZERO)
            await _ticks(40)
            var from := player.position
            var start_yaw := player.yaw
            var expected := Vector3.FORWARD.rotated(Vector3.UP, start_yaw)
            var previous := from
            var max_drift := 0.0
            var min_alignment := 1.0
            var max_heading_error := 0.0
            var max_intent_error := 0.0
            var max_yaw_error := 0.0
            _press(2, right)
            for i in 8:
                var step := deg_to_rad(degrees) / 8.0
                var across_split := Vector2(size.x * .4, right.y)
                _drag(2, across_split if i % 2 == 0 else right, Vector2(-step * pixels_per_radian, 0))
                await _ticks(2)
                _check(touch.move_finger == 1 and touch.look_finger == 2, "Crossed look touch lost ownership")
                max_intent_error = maxf(max_intent_error, player.movement_intent.distance_to(expected))
                max_yaw_error = maxf(max_yaw_error, absf(angle_difference(player.yaw, start_yaw + step * (i + 1))))
                max_heading_error = maxf(max_heading_error, absf(angle_difference(player.travel_heading, PI + start_yaw)))
                var actual := player.get_real_velocity() * Vector3(1, 0, 1)
                min_alignment = minf(min_alignment, actual.normalized().dot(expected))
                var displacement := (player.position - from) * Vector3(1, 0, 1)
                max_drift = maxf(max_drift, displacement.cross(expected).length())
                _check((player.position - previous).dot(expected) > .015, "Forward trajectory stalled or reversed")
                previous = player.position
            var label := "%s° orbit at water depth %.1f" % [degrees, depth]
            _check(max_yaw_error < .003 and max_intent_error < .003, "Camera or movement intent mismatch: " + label)
            _check(min_alignment > .995 and max_heading_error < .025 and max_drift < .035,
                "Velocity, heading or trajectory redirected: " + label)
            print("%s | yaw error %.4f rad | intent error %.4f | min velocity dot %.4f | heading error %.4f rad | drift %.4f m"
                % [label, max_yaw_error, max_intent_error, min_alignment, max_heading_error, max_drift])
            _press(2, right, false)
            var released_yaw := player.yaw
            await _ticks(4)
            _check(player.movement_intent.distance_to(expected) < .003 and player.yaw == released_yaw,
                "Look release redirected the player")
        var expected_state: CampHumanoidMotor.Locomotion = [CampHumanoidMotor.Locomotion.LAND, CampHumanoidMotor.Locomotion.WADE,
            CampHumanoidMotor.Locomotion.SWIM][[0.0, .6, 6.0].find(depth)]
        _check(player.locomotion == expected_state, "Unexpected test-pad locomotion")

    var expected := player.movement_intent
    player.toggle_dive()
    player.pitch = -.6
    var before_dive := player.position.y
    _press(2, right)
    _drag(2, right, Vector2(-PI * pixels_per_radian, 0))
    await _ticks(110)
    _check(player.underwater() and player.position.y < before_dive - 1.8
        and player.movement_intent.distance_to(expected) < .003
        and (player.get_real_velocity() * Vector3(1, 0, 1)).normalized().dot(expected) > .995,
        "Diving changed the horizontal bearing or lost pitch-based depth control")
    _press(2, right, false)
    player.reset_camera()
    await _ticks(3)
    _check(absf(angle_difference(player.yaw, player.travel_heading + PI)) < .003
        and player.movement_intent.distance_to(expected) < .003, "Camera reset redirected held movement")
    _drag(1, left + Vector2.RIGHT * touch.radius, Vector2.ZERO)
    await _ticks(24)
    var turned_intent := player.movement_intent
    player.reset_camera()
    await _ticks(3)
    _check(player.movement_intent.distance_to(turned_intent) < .003
        and absf(angle_difference(player.yaw, player.travel_heading + PI)) < .003,
        "Centering behind a deliberate turn replaced the gesture's camera reference")
    _press(2, right)
    var uncanceled_yaw := player.yaw
    _drag(2, right, Vector2(pixels_per_radian, 0))
    _press(2, right, false, true)
    await _ticks(2)
    _check(touch.move_finger == 1 and player.yaw == uncanceled_yaw, "Canceled look altered an active gesture")

    # Reset the camera to a different bearing, then keep the same thumb down
    # while passing through neutral and beginning a fresh gesture.
    player.yaw = -PI * .5
    _drag(1, left + forward * .18, Vector2.ZERO)
    await _ticks(2)
    _check(player.movement_intent.normalized().dot(expected) > .995, "Dead zone jitter recaptured the camera")
    _drag(1, left, Vector2.ZERO)
    _drag(1, left + forward, Vector2.ZERO)
    await _ticks(32)
    _check(player.movement_intent.dot(Vector3.RIGHT) > .995, "Neutral did not rearm the same finger")
    _press(1, left, false)
    player.yaw = 0.0
    _press(1, left)
    _drag(1, left + forward * .55, Vector2.ZERO)
    await _ticks(36)
    _check(player.movement_intent.normalized().dot(Vector3.FORWARD) > .995
        and player.get_real_velocity().z < -.5 and player.get_real_velocity().z > -1.15,
        "Released gesture did not recapture heading and analog speed")
    _drag(1, Vector2(size.x * .7, left.y), Vector2.ZERO)
    await _ticks(24)
    _check(touch.move_finger == 1 and touch.look_finger == -1 and absf(player.yaw) < .003
        and player.get_real_velocity().x > .8, "Crossed movement touch did not steer right")
    _drag(1, left - Vector2.RIGHT * touch.radius, Vector2.ZERO)
    var lowest_speed := player.planar.length()
    var reversed := false
    for frame in 32:
        await _ticks(1)
        var actual := player.get_real_velocity() * Vector3(1, 0, 1)
        var heading := Vector3(sin(player.travel_heading), 0, cos(player.travel_heading))
        _check(actual.length() < .08 or actual.normalized().dot(heading) > .995, "Reversal slid sideways")
        if not reversed:
            lowest_speed = minf(lowest_speed, actual.length())
            reversed = actual.x < -.08
    _check(reversed and lowest_speed < .18 and player.get_real_velocity().x < -1.0,
        "Reversal failed to brake and accelerate in the opposite direction")
    for step in 5:
        var steer := Vector2.RIGHT if step % 2 == 0 else Vector2.LEFT
        _drag(1, left + steer * touch.radius, Vector2.ZERO)
        await _ticks(3)
        _check(player.movement_intent.dot(Vector3(steer.x, 0, 0)) > .995 and player.planar.length() <= 1.86,
            "Rapid joystick reversals lost input or overshot swim speed")
    await _ticks(36)
    _check(player.get_real_velocity().x > 1.0, "Rapid reversals did not settle toward the last input")
    touch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    await _ticks(22)
    _check(touch.move_finger == -1 and player.movement_intent == Vector3.ZERO
        and player.planar == Vector3.ZERO, "Focus loss left active input")

    camp.hud.steering_button.pressed.emit()
    player.yaw = 0.0
    _press(1, left)
    _drag(1, left + forward, Vector2.ZERO)
    await _ticks(16)
    _press(2, right)
    _drag(2, right, Vector2(-PI * .5 * pixels_per_radian, 0))
    await _ticks(36)
    _check(player.movement_intent.dot(Vector3.LEFT) > .995 and player.get_real_velocity().x < -.8,
        "Optional camera-relative steering did not follow the orbit")
    touch.cancel()

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
