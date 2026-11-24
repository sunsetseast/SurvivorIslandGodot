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
        "freshwater spring": camp.site.ground(103.3, 35.8), "quiet alcove": camp.site.ground(29, 85.5),
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
    var original_yaw := camp.player.yaw
    camp.player.orbit(Vector2(44, -720))
    _check(camp.player.yaw != original_yaw and camp.player.pitch <= .42, "Camera orbit or pitch limits failed")
    print("Tonsai result: ", camp.player.travel_distance, " m continuously walked; ",
        camp.simulation.arrivals, " NPC arrivals; ", failures, " failures")
    quit(int(failures > 0))

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
