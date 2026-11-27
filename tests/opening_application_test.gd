extends SceneTree
## Fault injection wraps the real app/providers; successful camp loads use Tonsai.
class FaultStore extends LocalDataStore:
    var fail_writes := false
    var fail_reads := false
    var lose_verification := false
    func write(key: String, value: String) -> bool:
        if key.begins_with("slot-") and fail_writes:
            return false
        var ok := super.write(key, value)
        if ok and key.begins_with("slot-") and lose_verification:
            fail_reads = true
        return ok
    func read(key: String) -> Variant:
        return null if fail_reads and key.begins_with("slot-") else super.read(key)
class FaultLocations extends LocationManager:
    var fail_next := false
    func enter(id: String, active: GameSession, preferences: PlayerProfile) -> bool:
        if fail_next:
            fail_next = false
            return false
        return super.enter(id, active, preferences)
var app: SurvivorGameApp
var store: FaultStore
var failures := 0
func _initialize() -> void:
    call_deferred("run")
func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", label)
func frames(count_value := 3) -> void:
    for frame in count_value:
        await physics_frame
func tap(control: Button) -> void:
    var point := control.get_global_rect().get_center()
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.position = point
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        root.push_input(event, true)
        await frames(2)
func start(count_value: int) -> Dictionary:
    app._configured = true
    app.selection_setup.selected_id = 1
    app.division.seed_value = 42
    app.division.count = count_value
    app.division.assign(app.contestant_catalog)
    app._slots(true)
    await frames()
    await tap(app._actions.slot1)
    check(is_instance_valid(app._marooning) and app.saves.inspect(1).status == "empty", "Slot starts marooning without permanent save")
    return app._opening_ticket.duplicate(true)
func complete(ticket: Dictionary) -> void:
    var handoff := OpeningFixture.session(ticket.configuration, app.contestant_catalog).result()
    var invalid := handoff.duplicate(true)
    invalid.version = 1
    app._arrival(invalid, ticket.token)
    check(app.saves.inspect(1).status == "empty" and app._completed_opening.is_empty(), "Invalid callback cannot initialize")
    var retired: WeakRef = weakref(app._marooning)
    app._marooning.completed.emit(handoff)
    await frames()
    check(app.screen == SurvivorGameApp.Screen.ARRIVAL and retired.get_ref() == null, "Validated arrival summary fully releases marooning")
    var original: Dictionary = app._completed_opening.duplicate(true)
    app._arrival(handoff, ticket.token)
    app._arrival(handoff, "stale-token")
    check(app._completed_opening == original, "Duplicate and stale completion callbacks fenced")
func run() -> void:
    root.size = Vector2i(956, 440)
    app = load("res://application/game_app.tscn").instantiate()
    root.add_child(app)
    await frames(5)
    check(app.contestant_catalog.available, "Explicit private stage required; no synthetic replacement")
    if not app.contestant_catalog.available:
        app.free()
        quit(1)
        return
    store = FaultStore.new("opening-app-" + GameStateData.new_id())
    app.profile = PlayerProfile.new(store)
    app.saves = LocalSaveProvider.new(store)
    app.locations.free()
    app.locations = FaultLocations.new()
    app.add_child(app.locations)
    var ticket := await start(2)
    app._marooning.restart_scramble()
    check(app.saves.inspect(1).status == "empty", "Restart before arrival creates no save")
    app._close_marooning()
    check(app.saves.inspect(1).status == "empty" and app._opening_ticket.is_empty(), "Exit before arrival creates no save")
    ticket = await start(2)
    await complete(ticket)
    store.fail_writes = true
    await tap(app._actions.begin_day1)
    check(app.screen == SurvivorGameApp.Screen.ARRIVAL and app.session == null and app.saves.inspect(1).status == "empty", "Initial failure retains completed handoff")
    store.fail_writes = false
    await tap(app._actions.begin_day1)
    check(app.session != null and app.save_revision == 1 and app.saves.inspect(1).state.tick == 0, "Retry commits exactly one Day 1 tick 0 checkpoint")
    if app.session == null:
        app.free()
        quit(1)
        return
    var original := app.session.checkpoint()
    check(app.locations.camp.inhabitants.size() == 8 and not app.locations.camp.props.campfire.lit, "Nine actual tribemates, unlit fire")
    app._begin_day1()
    check(app.save_revision == 1, "Repeated Begin creates no additional revision")
    app._show_supplies()
    check(app.screen == SurvivorGameApp.Screen.SUPPLIES and app._status.text.contains("Rice sack"), "Actual tribal supplies interface")
    app._close_supplies()
    check(not app.locations.camp.player.locked, "Supplies returns normal camp controls")
    app._exit_session()
    app._load(1)
    check(app.session.checkpoint().opening_history == original.opening_history and app.session.checkpoint().tribal_inventory == original.tribal_inventory, "Continue preserves all new durable fields")
    app._exit_session()
    app._slots(false)
    await frames()
    await tap(app._actions.slot1)
    check(app.session != null and app.session.checkpoint().configuration == original.configuration, "Load input restores permanent configuration")
    app._exit_session()
    app.saves.erase(1)
    ticket = await start(3)
    await complete(ticket)
    (app.locations as FaultLocations).fail_next = true
    await tap(app._actions.begin_day1)
    check(app.session == null and app.screen == SurvivorGameApp.Screen.MAIN and app.saves.inspect(1).status == "valid", "Camp load failure retains committed checkpoint")
    await frames()
    await tap(app._actions.continue)
    check(app.session != null and app.locations.camp.inhabitants.size() == 5, "Continue recovers after camp failure with six actual tribemates")
    app._exit_session()
    app.saves.erase(1)
    ticket = await start(2)
    await complete(ticket)
    var unrelated := SeasonSimulation.new(app.profile.guest_id, GameStateData.new_id(), 1)
    app.saves.write(1, unrelated.snapshot(), 0)
    app._begin_day1()
    check(app.session == null and app.saves.inspect(1).state.season_id == unrelated.season_id, "Late slot conflict never overwritten")
    app._abandon_opening()
    app.saves.erase(1)
    ticket = await start(3)
    await complete(ticket)
    store.lose_verification = true
    app._begin_day1()
    check(app.session == null and not app._completed_opening.is_empty(), "Uncertain verification retains handoff")
    store.lose_verification = false
    store.fail_reads = false
    app._begin_day1()
    check(app.session != null and app.save_revision == 1, "Retry recognizes already-committed identity without rewriting")
    app._exit_session()
    app.saves.erase(1)
    ticket = await start(2)
    app.auth.account = "8bc5b36f-d363-4cbc-995d-6dc83ba215de"
    app._identity_changed()
    check(app._opening_ticket.is_empty() and not is_instance_valid(app._marooning) and LocalSaveProvider.new(store).inspect(1).status == "empty", "Ownership change cancels ticket without creating save")
    app._arrival(OpeningFixture.session(ticket.configuration, app.contestant_catalog).result(), ticket.token)
    check(app.session == null, "Old account callback rejected")
    ticket = await start(3)
    await complete(ticket)
    app._begin_day1()
    check(app.session != null and app.saves.store.storage_prefix != store.storage_prefix, "Account season committed in its own local namespace")
    check(app.cloud.slot_status(1, app.saves.inspect(1)) == "Saved locally · cloud support pending" and app.cloud._due.is_empty(), "V2 account checkpoint retained without claiming cloud sync")
    app._exit_session()
    app.saves.erase(1)
    app.cloud.reset(1)
    app.free()
    for key: String in ["guest", "preferences"]:
        store.erase(key)
    await frames()
    print("Permanent application lifecycle: ", failures, " failures")
    quit(1 if failures else 0)
