extends SceneTree

const OWNER := "11111111111111111111111111111111"
const SEASON := "22222222222222222222222222222222"
const COMMAND := "33333333333333333333333333333333"
const TOPIC := "44444444444444444444444444444444"
var failures := 0

func _initialize() -> void:
    var sim := SeasonSimulation.new(OWNER, SEASON, -7167511679230800209)
    var session := LocalGameSession.new(sim, OWNER)
    _check(sim.roster.size() == 18 and sim.camps.size() == 3, "Initial roster")
    for location: String in SeasonCatalog.LOCATIONS:
        _check(sim.camps[location].people.size() == 6, "Tribe size")
    var request := {"id": COMMAND, "actor": "explorer", "kind": "talk.begin", "target": "cirie"}
    session.bind_physical_location("tonsai")
    _check(not sim.command(SEASON, request, {}).ok, "Foreign principal")
    _check(not session.submit(request).ok, "Unobserved talk")
    _check(not session.view("camp-2").has("cast") and sim.project(SEASON, "tonsai").is_empty(), "Foreign projection")
    session.observe_talk("cirie", 4, true)
    _check(not session.submit(request).ok, "Out of range talk")
    session.observe_talk("cirie", 1, true)
    _check(session.submit(request).ok, "Observed talk")
    request.merge({"id": TOPIC, "kind": "talk.respond", "topic": "water"}, true)
    var result := session.submit(request)
    _check(result.ok and result.event.type == "conversation_reply", "Reply event")
    _check(session.submit(request) == result and session.view("tonsai").knowledge.size() == 1, "Receipt replay")
    _check(sim.camps.tonsai.people.cirie.journal.size() == 1 and sim.camps.tonsai.people.yul.journal.is_empty(), "Private journal")
    request.merge({"id": GameStateData.new_id(), "kind": "talk.end"}, true)
    _check(session.submit(request).ok, "Close conversation")
    session.bind_physical_location("")
    session.step(99)
    _check(sim.tick == 4, "Bounded catch-up")
    _check(GameStateData.pose({"location": "tonsai", "position": [0, 3, 0],
        "heading": 0.2, "yaw": 0.4, "pitch": -0.4, "underwater": false}), "Valid pose")
    var snapshot := sim.snapshot()
    var encoded := SaveCodec.encode(snapshot, 1, 1750000000)
    var decoded := SaveCodec.decode(encoded)
    if decoded.status != "valid":
        printerr("FAIL: checkpoint codec returned ", decoded.status)
        quit(1)
        return
    _check(decoded.state.rng_state == snapshot.rng_state, "RNG precision")
    _test_generations(snapshot, encoded)
    var restored := SeasonSimulation.restore(decoded.state)
    var start := Time.get_ticks_usec()
    for index in 2400:
        sim.advance("")
        restored.advance("")
    var per_step_usec := float(Time.get_ticks_usec() - start) / 4800.0
    _check(sim.day() == 2 and sim.camps["camp-2"].arrivals > 0, "Day and off-screen scheduling")
    _check(sim.snapshot() == restored.snapshot(), "Continued RNG trajectory")
    print("Foundation: ", failures, " failures; ", snappedf(per_step_usec, .01), " μs mean/tick for 18 contestants")
    quit(int(failures > 0))

func _test_generations(snapshot: Dictionary, encoded: String) -> void:
    var store := LocalDataStore.new("test-" + GameStateData.new_id())
    var provider := LocalSaveProvider.new(store)
    _check(provider.write(1, snapshot, 0).status == "valid", "Create slot")
    _check(provider.write(1, snapshot, 0).status == "conflict", "Reject stale revision")
    _check(provider.write(1, snapshot, 1).status == "valid", "Checkpoint slot")
    store.write("slot-1-1", encoded.left(77))
    var recovered := provider.inspect(1)
    _check(recovered.get("recovered") == true and recovered.get("save_revision") == 1, "Recover truncated write")
    var old: Dictionary = JSON.parse_string(JSON.parse_string(encoded).payload)
    old.schema = 1
    old.state.pose = {"location": "tonsai", "position": [0, 3, 0], "heading": .2, "yaw": .4, "pitch": -.4}
    var migrated := SaveCodec.decode(_wrap(old))
    _check(migrated.status == "valid" and migrated.state.pose.underwater == false and migrated.schema == 2, "Schema 1 migration")
    old.schema = 99
    store.write("slot-1-1", _wrap(old))
    _check(provider.inspect(1).status == "unsupported" and provider.write(1, snapshot, 1).status == "unsupported", "Preserve future schema")
    _check(provider.erase(1) and provider.inspect(1).status == "empty", "Delete both generations")
    _check(provider.write(2, snapshot, 0).status == "valid" and provider.inspect(1).status == "empty", "Slots are independent")
    snapshot.pose = {"location": "tonsai", "position": [900, -2000, 0], "heading": 9}
    _check(provider.write(2, snapshot, 1).status == "invalid_save", "Invalid pose rejected")
    provider.erase(2)

func _wrap(envelope: Dictionary) -> String:
    var payload := JSON.stringify(envelope, "", false, true)
    return JSON.stringify({"payload": payload, "sha256": payload.sha256_text()})

func _check(ok: bool, detail: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", detail)
