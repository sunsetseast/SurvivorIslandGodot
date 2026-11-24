extends SceneTree

var failures := 0

func _initialize() -> void:
    call_deferred("_test")

func _check(ok: bool, detail: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", detail)

func _test() -> void:
    var app := load("res://application/game_app.tscn").instantiate() as SurvivorGameApp
    root.add_child(app)
    # Keep this test isolated from development saves.
    var store := LocalDataStore.new("application-test-" + GameStateData.new_id())
    app.profile = PlayerProfile.new(store)
    app.saves = LocalSaveProvider.new(store)
    for level: float in [.65, 1.4]:
        _check(app.profile.set_preference("sensitivity", level), "Write sensitivity preference")
        _check(PlayerProfile.new(store).preferences.sensitivity == level, "Reload exact sensitivity preset")
    app.profile.set_preference("sensitivity", 1.0)
    app._new(1)
    var camp := app.locations.camp
    if camp == null:
        printerr("FAIL: application did not load camp")
        quit(1)
        return
    for frame in 18:
        await physics_frame
    _check(camp.inhabitants.size() == 5, "Tonsai cast size")
    _check(camp.begin_talk() and not camp.respond(&"water").is_empty(), "Session conversation")
    var before := app.session.view("tonsai")
    _check(before.knowledge.size() == 1 and app.save_revision >= 2, "Conversation checkpoint")
    app._suspend(true)
    for frame in 60:
        await physics_frame
    _check(app.session.current_tick() == int(before.tick), "Suspended time advanced")
    app._suspend(false)
    var session := app.session
    var point := camp.player.position
    var heading := camp.player.travel_heading
    _check(camp.checkpoint_player(), "Player pose checkpoint")
    app.locations.leave()
    for frame in 60:
        await physics_frame
    _check(session.current_tick() > int(before.tick), "Clock stopped without location")
    _check(app.locations.enter("tonsai", session, app.profile), "Location reload")
    _check(app.locations.camp.player.position.distance_to(point) < .1, "Location reload lost player position")
    _check(absf(angle_difference(app.locations.camp.player.travel_heading, heading)) < .01, "Location reload lost heading")
    _check(app.session.view("tonsai").knowledge == before.knowledge, "Location reload lost journal")
    app._exit_session()
    _check(app.screen == SurvivorGameApp.Screen.MAIN and app.session == null, "Exit to menu")
    app._load(1)
    _check(app.session.view("tonsai").season_id == before.season_id, "Continue season")
    _check(app.session.view("tonsai").knowledge == before.knowledge, "Continue journal")
    app._exit_session()
    app._slots(false)
    var saved := app.saves.inspect(1)
    app._delete(1, saved.fingerprint)
    _check(app.saves.inspect(1).status == "valid", "Delete requires confirmation")
    app._delete(1, saved.fingerprint)
    _check(app.saves.inspect(1).status == "empty", "Confirmed delete removes slot")
    app.queue_free()
    await process_frame
    app = null
    camp = null
    session = null
    LocalSaveProvider.new(store).erase(1)
    store.erase("guest")
    store.erase("preferences")
    print("Application lifecycle: ", failures, " failures")
    quit(int(failures > 0))
