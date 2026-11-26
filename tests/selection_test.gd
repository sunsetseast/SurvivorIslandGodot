extends SceneTree
var failures := 0
func _initialize() -> void:
    call_deferred("run")
func check(value: bool, detail: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", detail)
func fixture() -> SurvivorContestantCatalog:
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
        entries.append({"id":1001 + index,"name":"Technical fixture %d" % index,
            "gender":"male" if index % 2 == 0 else "female", "trait":["Physical","Mental","Social"][index / 6],
            "style":"Fixture", "original_season":"Test", "appearance_season":"Test",
            "attributes":attributes,"totals":{"Physical":25,"Mental":25,"Social":25},"defaults":defaults,
            "portrait_path":"res://private_cast/portraits/fixture.webp","model_path":""})
    var file := FileAccess.open("user://selection-fixture.json", FileAccess.WRITE)
    file.store_string(JSON.stringify({"version":1,"entries":entries}))
    file.close()
    return SurvivorContestantCatalog.new("user://selection-fixture.json")
func run() -> void:
    var unavailable := SurvivorContestantCatalog.new("res://absent-private-catalog.json")
    check(not unavailable.available and unavailable.all().is_empty(), "Public builds do not invent a replacement cast")
    var unavailable_screen := SurvivorSelectionScreen.new()
    unavailable_screen.catalog = unavailable
    unavailable_screen.setup = SurvivorNewSeasonSetup.new()
    root.add_child(unavailable_screen)
    await process_frame
    check(unavailable_screen._select.disabled and unavailable_screen.actions.random.disabled, "Unavailable catalog disables selection and random")
    unavailable_screen.queue_free()
    await process_frame
    var catalog := fixture()
    check(catalog.all().size() == 18, "Technical catalog loads 18 entries")
    var copy := catalog.get_by_id(1001)
    copy.attributes.strength = 1
    copy.defaults.roles.append("changed")
    check(catalog.get_by_id(1001).attributes.strength == 5 and catalog.get_by_id(1001).defaults.roles.is_empty(), "Catalog and defaults isolate mutations")
    for kind: String in ["Physical", "Mental", "Social"]:
        check(catalog.eligible(kind).size() == 6, "Six entries per classification")
        check(catalog.eligible(kind, "female").size() == 3, "Intersect gender and classification")
    var setup := SurvivorNewSeasonSetup.new()
    var screen := SurvivorSelectionScreen.new()
    screen.catalog = catalog
    screen.setup = setup
    root.add_child(screen)
    await process_frame
    for entry: Dictionary in catalog.all():
        screen.choose(entry.id)
        screen.confirm_selection()
        check(setup.selected_id == entry.id and setup.validate(catalog), "Each contestant produces valid handoff")
    setup.information_mode = "Immersive"
    check(setup.ratings_for(catalog.all()[0], false).is_empty(), "Immersive withholds opponent ratings")
    check(setup.ratings_for(catalog.all()[0], true).attributes.size() == 27, "Own ratings remain visible")
    check(not setup.impressions_for(catalog.all()[0]).has("defaults"), "No runtime secrets in impressions")
    setup.trait_filter = "Physical"
    setup.gender_filter = "female"
    screen._filter()
    check(screen._eligible.size() == 3 and screen._eligible.any(func(e: Dictionary) -> bool: return e.id == setup.selected_id), "Filter moves selection into eligible roster")
    for iteration in 30:
        screen.random_select()
        check(screen._eligible.any(func(e: Dictionary) -> bool: return e.id == setup.selected_id), "Random stays eligible")
    await process_frame
    check(screen.preview.status_text == "Preview unavailable", "Unavailable preview cannot block selection")
    var retired: WeakRef = weakref(screen.preview)
    screen.queue_free()
    await process_frame
    check(retired.get_ref() == null, "Preview tears down on exit")
    # One neutral primitive is a technical fixture, never a contestant replacement.
    var model := Node3D.new()
    var mesh := MeshInstance3D.new()
    mesh.mesh = BoxMesh.new()
    model.add_child(mesh)
    mesh.owner = model
    var player := AnimationPlayer.new()
    var library := AnimationLibrary.new()
    var idle := Animation.new()
    idle.length = 1.0
    library.add_animation("Idle", idle)
    player.add_animation_library("", library)
    model.add_child(player)
    player.owner = model
    var packed := PackedScene.new()
    packed.pack(model)
    model.free()
    ResourceSaver.save(packed, "user://preview-fixture.tscn")
    var preview := SurvivorCharacterPreview.new()
    root.add_child(preview)
    preview.show_contestant({"model_path":"user://preview-fixture.tscn"})
    await process_frame
    check(preview._pivot != null and preview._world.get_child_count() == 5, "Exactly one selected technical model")
    var idle_player := preview._pivot.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
    check(idle_player.current_animation == "Idle" and idle_player.is_playing(), "Supported idle animation starts")
    check(preview._camera.position.z > preview._radius and preview._camera.near > 0, "Model bounds produce valid camera framing")
    preview._rotate_model(80)
    check(preview._pivot.rotation.y != 0, "Drag rotates model")
    preview.show_contestant({"model_path":"user://preview-fixture.tscn"})
    preview.show_contestant({})
    await process_frame
    check(preview._pivot == null and preview._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Rapid switching never displays stale model")
    preview.teardown()
    check(preview.get_child_count() == 0, "Teardown releases viewport and resources")
    preview.queue_free()
    var private_catalog := SurvivorContestantCatalog.new()
    if private_catalog.available:
        check(private_catalog.all().size() == 18, "Private catalog has 18 IDs")
        for kind: String in ["Physical", "Mental", "Social"]:
            check(private_catalog.eligible(kind).size() == 6, "Private classifications preserved")
        var portrait_preview := SurvivorCharacterPreview.new()
        root.add_child(portrait_preview)
        for id in range(1, 19):
            var entry := private_catalog.get_by_id(id)
            check(entry.attributes.size() == 27 and entry.attributes.has("campcraft"), "All private IDs retain 27 ratings")
            setup.selected_id = id
            check(setup.validate(private_catalog), "Every real ID hands off")
            portrait_preview.show_contestant(entry)
            await process_frame
            check(portrait_preview._portrait.texture != null and not portrait_preview._label.visible, "Each private portrait displays without an unavailable overlay")
        portrait_preview.queue_free()
    # Navigation never writes a season; technical season remains a distinct action.
    var app := load("res://application/game_app.tscn").instantiate() as SurvivorGameApp
    root.add_child(app)
    await process_frame
    var store := LocalDataStore.new("selection-test-" + GameStateData.new_id())
    app.profile = PlayerProfile.new(store)
    app.saves = LocalSaveProvider.new(store)
    for cycle in 4:
        app._new_game()
        await process_frame
        check(app._title_environment == null and app.session == null, "Selection releases title and creates no season")
        app._main()
        await process_frame
        check(app._selection == null and app._title_environment != null, "Return releases selection")
    check(app.saves.inspect(1).status == "empty", "Browsing never writes save")
    app._credits()
    check(app._actions.has("technical"), "Technical-season access retained")
    app._settings()
    app._slots(false)
    app._accounts.open()
    check(app.session == null, "Existing menu destinations remain season-free")
    app.queue_free()
    await process_frame
    DirAccess.remove_absolute("user://selection-fixture.json")
    DirAccess.remove_absolute("user://preview-fixture.tscn")
    print("Phase 4B selection/preview/handoff: ", failures, " failures")
    quit(int(failures > 0))
