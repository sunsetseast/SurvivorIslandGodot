extends SceneTree
var failures := 0
func _initialize() -> void:
    call_deferred("run")
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)
static func fixture() -> SurvivorContestantCatalog:
    var entries: Array = []
    for index in 18:
        var attributes := {}
        for group: Dictionary in SurvivorContestantCatalog.GROUPS.values():
            for key: String in group:
                attributes[key] = 5
        var defaults := {}
        for key: String in SurvivorContestantCatalog.DEFAULT_FIELDS:
            match SurvivorContestantCatalog.DEFAULT_FIELDS[key]:
                TYPE_INT: defaults[key] = 0
                TYPE_BOOL: defaults[key] = true
                TYPE_ARRAY: defaults[key] = []
                _: defaults[key] = null
        entries.append({"id":1 + index,"name":"Technical fixture %d" % index,
            "gender":"male" if index % 2 == 0 else "female", "trait":["Physical","Mental","Social"][index / 6],
            "style":"Fixture", "original_season":"Test", "appearance_season":"Test",
            "attributes":attributes,"totals":{"Physical":25,"Mental":25,"Social":25},"defaults":defaults,
            "portrait_path":"res://private_cast/portraits/fixture.webp","model_path":""})
    var file := FileAccess.open("user://selection-fixture.json", FileAccess.WRITE)
    file.store_string(JSON.stringify({"version":1,"entries":entries}))
    file.close()
    return SurvivorContestantCatalog.new("user://selection-fixture.json")
func run() -> void:
    root.size=Vector2i(956,440)
    root.content_scale_size=Vector2i(1280,720)
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available:
        catalog = fixture()
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = 18
    for count_value in [2, 3]:
        var division := SurvivorSeasonConfiguration.new()
        division.count = count_value
        division.assign(catalog)
        var preview := MarooningPreview.new()
        preview.catalog = catalog
        preview.configuration = division.configuration(catalog, setup)
        var original := preview.configuration.duplicate(true)
        root.add_child(preview)
        await process_frame
        await physics_frame
        check(preview.cast.size() == 18 and preview.cast.has(18), "18 IDs exactly once")
        check(preview.cast[18] == preview.player, "Selected actor controlled")
        check(preview.routes.size() == count_value, "Every tribe has future route")
        check(preview.bay.markers.has("raft-mount-%d" % (count_value - 1)), "Matching rafts")
        check(not preview.bay.markers.has("raft-mount-%d" % count_value), "No spare raft")
        for id: String in ["deck", "host", "cargo-rice-sack", "cargo-crate", "cargo-rope", "cargo-basket", "cargo-cooking-pot", "cargo-survival-kit", "reward-dock", "player-landing", "future-camp-transition", "rival-exit-0", "rival-exit-1"]:
            check(preview.bay.markers.has(id), "Marker " + id)
        for a: int in preview.cast:
            for b: int in preview.cast:
                if a != b:
                    check(preview.cast[a].position.distance_to(preview.cast[b].position) > 1.0, "Spawn clearance")
        check(preview.player.locked, "Intro locks motor")
        if count_value == 2:
            preview.finish_intro()
        else:
            preview.elapsed = preview.shots.size() * 5.0
            await process_frame
        preview.session.ready()
        preview.session.start(false)
        for frame in 55:
            await physics_frame
        check(not preview.player.locked and preview.player.camera.current, "Skip hands control back")
        if OS.get_environment("MAROONING_TOUCH_SMOKE")=="1":
            print("WINDOW ",root.size," safe=",preview.touch.safe)
            for key: String in preview.hud.actions:
                var button: Button=preview.hud.actions[key]
                if button.visible: print("GUI ",key," ",button.get_global_rect())
        var left := preview.touch.home()
        var right := preview.touch.size*Vector2(.58,.3)
        print("TOUCH_LAYOUT root=",root.get_visible_rect()," viewport=",preview.get_viewport().get_visible_rect()," touch=",preview.touch.size," available=",preview.touch.movement_available," locked=",preview.player.locked)
        press(401, left)
        press(902, right)
        drag(401, left + Vector2(0, -55))
        var yaw_before := preview.player.yaw
        drag(902, right + Vector2(60, 0))
        for frame in 8:
            await physics_frame
        await process_frame
        print("MOVE_LOOK ",count_value," owners=",preview.touch.move_finger,"/",preview.touch.look_finger," yaw=",yaw_before," -> ",preview.player.yaw," point=",right)
        check(preview.player.touch_direction.length() > .2, "Touch movement remains active during orbit")
        check(absf(preview.player.yaw - yaw_before) > .01 and absf(preview.player.yaw - yaw_before) < 1, "Absolute finger positions reject corrupted relative deltas")
        preview.touch.cancel()
        check(preview.player.touch_direction.is_zero_approx() and preview.touch.move_finger == -1 and preview.touch.look_finger == -1, "Touch cancellation releases both fingers")
        if OS.get_environment("MAROONING_TOUCH_SMOKE")=="1":
            preview.queue_free()
            await process_frame
            continue
        place(preview,Vector3(0,preview.layout.deck_y+.15,7))
        for frame in 30:
            await physics_frame
        check(preview.player.is_on_floor() and absf(preview.player.position.y - preview.layout.deck_y) < .2, "Deck supports motor")
        place(preview,Vector3(-3.0, preview.layout.deck_y + .15, -3.5))
        preview.player.yaw = 0
        preview.player.sync_camera()
        preview.player.touch_direction = Vector2(0, -1)
        for frame in 420:
            await physics_frame
        preview.touch.cancel()
        print("Host ramp arrival: ", preview.player.position)
        check(preview.player.position.y > preview.layout.deck_y + 2.3 and preview.player.position.z < -8.5, "Existing motor climbs visible host ramp")
        place(preview,Vector3(0,preview.layout.bed(0,178)+.15,178))
        for frame in 60:
            await physics_frame
        check(preview.player.is_on_floor(), "Real landing supports motor")
        place(preview,preview.layout.reward+Vector3(-1,.3,0))
        for frame in 60:
            await physics_frame
        check(preview.player.is_on_floor(), "Dock supports motor")
        var test_transform := preview.player.global_transform
        test_transform.origin = Vector3(3.2,preview.layout.deck_y+.05,0)
        check(preview.player.test_move(test_transform,Vector3(3,0,0)), "Starboard railing rejects penetration")
        test_transform.origin = Vector3(0,preview.layout.deck_y+.05,-6)
        check(preview.player.test_move(test_transform,Vector3(0,0,-4)), "Cabin wall rejects penetration")
        var nav_map: RID = preview.get_world_3d().navigation_map
        for item: Dictionary in preview.scramble.simulation.items.values():
            var path := NavigationServer3D.map_get_path(nav_map,Vector3(0,preview.layout.deck_y,3),item.position,true)
            check(not path.is_empty() and path[path.size()-1].distance_to(item.position) < 1.2,"Cargo anchor reachable: " + item.id)
        place(preview,Vector3(0,preview.layout.deck_y+.15,7))
        preview.scramble.start()
        for frame in 3605:
            await physics_frame
        var sim := preview.scramble.simulation
        check(sim.phase == MarooningScramble.Phase.SCRAMBLE_COMPLETE, "Full gameplay timer completes")
        check(sim.items.size() == 50, "Conserves exactly 50 supplies")
        var participants := {}
        var deliveries := {}
        for event: Dictionary in sim.events:
            if event.action in ["pickup","steal"] and event.outcome == "success":
                participants[event.actor] = true
            if event.action == "load" and event.outcome == "success":
                deliveries[event.tribe] = int(deliveries.get(event.tribe,0)) + 1
        print("Scramble pickups: ",participants.keys()," deliveries: ",deliveries)
        for actor_id: int in sim.actors:
            if actor_id==int(setup.selected_id): continue
            check(participants.has(actor_id) or float(preview.session.race.actors[actor_id].collect_until)<=7,"Each NPC collects or chooses a seeded early swim: "+str(actor_id))
        check(deliveries.size() == count_value, "Every tribe physically delivers")
        check(preview.configuration == original, "Configuration remains transient and unchanged")
        var reference: WeakRef = weakref(preview)
        preview.queue_free()
        await process_frame
        check(reference.get_ref() == null, "Preview released on exit")
    print("Marooning 2/3 tribe acceptance: ", failures, " failures")
    quit(1 if failures else 0)

func press(id: int, point: Vector2) -> void:
    var event := InputEventScreenTouch.new()
    event.index = id
    event.position = point
    event.pressed = true
    root.push_input(event, true)

func drag(id: int, point: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = id
    event.position = point
    event.relative = Vector2(9999, -9999)
    event.screen_relative = event.relative
    root.push_input(event, true)

func place(preview: MarooningPreview, point: Vector3) -> void:
    # Isolated geometry fixture; never used as normal journey/acceptance evidence.
    preview.touch.cancel()
    preview.player.velocity=Vector3.ZERO
    preview.player.planar=Vector3.ZERO
    preview.player.position=point
    preview.player.sync_camera()
