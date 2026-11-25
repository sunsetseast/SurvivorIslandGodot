extends SceneTree

var failures := 0

func check(value: bool, detail: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", detail)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var started := Time.get_ticks_msec()
    var app := load("res://application/game_app.tscn").instantiate() as SurvivorGameApp
    root.add_child(app)
    await process_frame
    print("Title startup milliseconds: ", Time.get_ticks_msec() - started)
    check(app.session == null and app.remote == null and app.locations.camp == null, "Title has no gameplay or multiplayer session")
    check(app._title_environment.find_children("*", "CollisionObject3D", true, false).is_empty(), "Title has no physics bodies")
    check(app._title_environment.find_children("*", "Camera3D", true, false).size() == 1, "One cinematic camera")
    check(ThemeDB.get_default_theme().default_font == app._ui.theme.default_font, "Separate game UI layers share the global font")
    var store := LocalDataStore.new("title-test-" + GameStateData.new_id())
    app.profile = PlayerProfile.new(store)
    app.saves = LocalSaveProvider.new(store)
    app._main()
    check(app._actions.continue.disabled, "No invented Continue save")
    app._new_game()
    check(app.session == null and app.saves.inspect(1).status == "empty", "New-game boundary does not create or save a season")
    app._settings()
    app._preference("economy", true)
    check(not app._title_environment.terrain.sun.shadow_enabled, "Economy changes presentation")
    app._preference("economy", false)
    check(app._title_environment.terrain.sun.shadow_enabled, "Full restores presentation")
    var retired: WeakRef = weakref(app._title_environment)
    app._new(1)
    await process_frame
    await process_frame
    check(retired.get_ref() == null, "Title released entering gameplay")
    check(app.session != null and app._title_environment == null, "Gameplay has no title camera")
    check(app.locations.camp.hud.theme.default_font == app._ui.theme.default_font, "Gameplay HUD inherits the same typography")
    app._exit_session()
    await process_frame
    check(app.session == null and app._title_environment != null, "Return creates only presentation")
    app.saves.erase(1)
    store.erase("guest")
    store.erase("preferences")
    app.queue_free()
    await process_frame
    print("Title boundary: ", failures, " failures")
    quit(int(failures > 0))
