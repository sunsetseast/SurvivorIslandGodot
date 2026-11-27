extends SceneTree
var failures := 0
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var catalog: SurvivorContestantCatalog = load("res://tests/marooning_test.gd").fixture()
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = 18
    var division := SurvivorSeasonConfiguration.new()
    division.assign(catalog)
    var preview := MarooningPreview.new()
    preview.catalog = catalog
    preview.configuration = division.configuration(catalog,setup)
    root.add_child(preview)
    await process_frame
    preview.finish_intro()
    preview.race.begin()
    var actor: Dictionary = preview.race.simulation.actors[18]
    actor.raft = actor.tribe
    preview.race.simulation.phase = MarooningRace.Phase.RAFT_RACE
    preview.race.update_hud()
    preview.scramble.set_physics_process(false)
    for button: Button in [preview.scramble.action_button,preview.scramble.drop_button,preview.scramble.steal_button]:
        button.show()
    for viewport_size: Vector2i in [Vector2i(956,440),Vector2i(812,375)]:
        root.size = viewport_size
        for frame in 5:
            await process_frame
        var bounds := preview.get_viewport().get_visible_rect()
        for button: Button in [preview.race.paddle,preview.race.rest,preview.race.jump,preview.scramble.action_button,preview.scramble.drop_button,preview.scramble.steal_button]:
            var css_size := button.get_global_rect().size * Vector2(viewport_size) / bounds.size
            if css_size.y < 44:
                failures += 1
                printerr("FAIL: touch height below 44 CSS pixels: ",button.text," ",css_size)
            if not bounds.encloses(button.get_global_rect()):
                failures += 1
                printerr("FAIL: ",viewport_size," clipped ",button.text," ",button.get_global_rect()," bounds ",bounds)
        print("Race UI bounds checked ",viewport_size)
    var safe := Rect2(Vector2(100,0),preview.get_viewport().get_visible_rect().size-Vector2(200,35))
    preview.touch.safe=safe
    preview._layout_hud_safe()
    for frame in 5: await process_frame
    for control: Button in [preview.race.paddle,preview.race.rest,preview.race.jump,preview.scramble.action_button,preview.scramble.drop_button]:
        if not safe.encloses(control.get_global_rect()):
            failures += 1
            printerr("FAIL: safe-area overlap ",control.text," ",control.get_global_rect()," ",safe)
    var actor_tribe: String = actor.tribe
    for type: String in preview.scramble.simulation.definitions:
        preview.race.simulation.scramble_result.secured[actor_tribe].append({"type":type})
    preview.race.finish()
    for frame in 5:
        await process_frame
    if not preview.get_viewport().get_visible_rect().encloses(preview.subtitle.get_global_rect()):
        failures += 1
        printerr("FAIL: Full equipment and personal contribution summary clipped")
    preview.queue_free()
    await process_frame
    print("Race UI: ",failures," failures")
    quit(1 if failures else 0)
