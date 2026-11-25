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
    var counts: Array[int] = []
    for cycle in 6:
        app._load(1)
        _check(app.locations.get_child_count() == 1, "One owned location")
        var retired := weakref(app.locations.camp)
        app._exit_session()
        await process_frame
        await process_frame
        _check(retired.get_ref() == null, "Retired camp released")
        _check(app.locations.get_child_count() == 0, "No orphaned location")
        counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
    _check(counts[-1] <= counts[1] + 2, "Bounded node count after warm caches")
    print("Repeated location node counts: ", counts)
    app._slots(false)
    var saved := app.saves.inspect(1)
    _test_cloud_listing(app, store, saved)
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

func _test_cloud_listing(app: SurvivorGameApp, store: LocalDataStore, entry: Dictionary) -> void:
    var row := {"id": "0c7ea6c4-5b74-4c5f-a09b-cd4692fb7ce7", "season_id": entry.state.season_id,
        "revision": 5.0, "day": 1.0, "tick": 10.0}
    var result := SurvivorCloudSaveService._decode_list([row])
    _check(result.status == "listed" and result.get("items") == [row], "PostgREST array reaches cloud list")
    _check(SurvivorCloudSaveService._decode_list([]).status == "listed", "Empty response is valid")
    for malformed: Variant in [null, {"status": "listed", "items": []}, [row, null], [{"id": row.id}]]:
        _check(SurvivorCloudSaveService._decode_list(malformed).status == "invalid_response",
            "Invalid or partial list cannot display as empty")

    _check(app._slot_sync_labels[1].text == "Saved locally only", "Guest slot indicator")
    app.cloud.set_process(false)
    app.cloud.bind(store, app.saves)
    _check(app.cloud.slot_status(1, entry) == "Sync pending", "Unacknowledged checkpoint")
    var sync := {"id": row.id, "season": entry.state.season_id, "revision": 5, "ack": int(entry.save_revision)}
    _check(app.cloud.write_record(1, sync), "Store test acknowledgement")
    app._cloud_updated(1, "saved")
    _check(app._slot_sync_labels[1].text == "Synced to cloud", "Local and cloud revisions are independent")
    sync.blocked = "conflict"
    _check(app.cloud.write_record(1, sync), "Store test conflict")
    _check(app.cloud.slot_status(1, entry) == "Conflict detected", "Revision conflict indicator")
    sync.blocked = "invalid_snapshot"
    _check(app.cloud.write_record(1, sync), "Store test failure")
    _check(app.cloud.slot_status(1, entry) == "Sync failed", "Terminal sync failure indicator")
    app.cloud.bind(null, null)
    for generation in 2:
        store.erase("sync-1-%d" % generation)
