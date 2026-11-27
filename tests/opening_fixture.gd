class_name OpeningFixture
extends RefCounted
## Synthetic data confined to isolated test stages; never an approved-cast fallback.
static func catalog() -> SurvivorContestantCatalog:
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
        entries.append({"id":index + 1, "name":"Technical fixture %d" % index,
            "gender":"male" if index % 2 == 0 else "female", "trait":["Physical","Mental","Social"][index / 6],
            "style":"Fixture", "original_season":"Test", "appearance_season":"Test", "attributes":attributes,
            "totals":{"Physical":25,"Mental":25,"Social":25}, "defaults":defaults,
            "portrait_path":"res://private_cast/portraits/fixture.webp", "model_path":""})
    DirAccess.make_dir_recursive_absolute("res://private_cast")
    var file := FileAccess.open(SurvivorContestantCatalog.PRIVATE_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify({"version":1,"entries":entries}))
    file.close()
    return SurvivorContestantCatalog.new()

static func config(cast: SurvivorContestantCatalog, count_value := 2) -> Dictionary:
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = 1
    var division := SurvivorSeasonConfiguration.new()
    division.seed_value = 42
    division.count = count_value
    division.assign(cast)
    return division.configuration(cast, setup)

static func session(config_value: Dictionary, cast: SurvivorContestantCatalog, empty := false, winner := "own") -> MarooningSession:
    var roster := {}
    var stations := {}
    var paths := {}
    var anchors: Array[Vector3] = []
    for index in 50:
        anchors.append(Vector3(index, 2, 0))
    var own := ""
    var rival := ""
    for tribe: Dictionary in config_value.tribes:
        stations[tribe.id] = Vector3.ZERO
        paths[tribe.id] = {"raft_id":tribe.id, "raft_mount":Vector3.ZERO, "heading":0,
            "destination":Vector3(0, 0, 180), "shore_center":Vector3(0, 0, 172),
            "stop_position":Vector3(0, 0, 158), "route_id":tribe.id + "-shore"}
        for member: Variant in tribe.members:
            roster[int(member)] = {"tribe":tribe.id, "position":Vector3.ZERO, "attributes":cast.get_by_id(int(member)).attributes}
        if int(config_value.selected) in tribe.members:
            own = tribe.id
        else:
            rival = tribe.id
    var sim := MarooningSession.new()
    sim.configure(config_value, roster, anchors, stations, [], paths, Vector3(0, 0, 100))
    sim.ready()
    sim.start(false)
    sim.events.append({"source":"navigation", "action":"deck_repath", "actor":1, "elapsed":0.0, "position":Vector3.ZERO, "held":"", "reason":"no_route_progress", "physical_retreat":false})
    # Exercise production deposits and event/contribution recording; transportation
    # endpoints are controlled fixtures, independent of the physics regressions.
    if not empty:
        for type: String in MarooningSupplyCatalog.definitions():
            var id := type + "-00"
            sim.scramble.items[id].state = MarooningScramble.State.CARRIED
            sim.scramble.items[id].actor = int(config_value.selected)
            sim.scramble.request(int(config_value.selected), "load", id)
            sim.elapsed += 3
            sim.scramble.advance_to(sim.elapsed)
        var enemy := int(config_value.tribes.filter(func(t: Dictionary) -> bool: return t.id == rival)[0].members[0])
        sim.scramble.items["rice-01"].state = MarooningScramble.State.CARRIED
        sim.scramble.items["rice-01"].actor = enemy
        sim.scramble.request(enemy, "load", "rice-01")
        sim.elapsed += 3
        sim.scramble.advance_to(sim.elapsed)
    sim.elapsed = 170.0 + 1.0 / 60.0
    sim.race.actors[int(config_value.selected)].fatigue = .123456789123
    sim.scramble.advance_to(sim.elapsed)
    sim.race.elapsed = sim.elapsed
    if winner == "unclaimed":
        sim.race.reward.merge({"status":"unclaimed", "location":"unclaimed", "time":150.0}, true)
    else:
        var tribe := own if winner == "own" else rival
        var claimant := int(config_value.tribes.filter(func(t: Dictionary) -> bool: return t.id == tribe)[0].members[0])
        sim.race.actors[claimant].position = sim.race.reward_position
        sim.race.claim(claimant)
        sim.race.reward.merge({"secured":true, "carrier":0, "location":"shore" if tribe == own else "raft"}, true)
    sim.sync_cargo()
    for member: Variant in config_value.tribes.filter(func(t: Dictionary) -> bool: return t.id == own)[0].members:
        sim.race.actors[int(member)].arrived = true
        sim.race.actors[int(member)]["arrival_time"] = 170.0
    var raft: Dictionary = sim.race.rafts[own]
    raft.arrived = true
    raft.arrival_time = 160.0
    raft.launch_time = 60.0
    raft.launch_reason = "collection_closed"
    raft.state = "regrouped"
    raft.cargo_location = "shore"
    for id: String in raft.cargo_ids:
        raft.delivered_ids[id] = true
    sim.race.phase = MarooningRace.Phase.ARRIVAL_COMPLETE
    sim.state = MarooningSession.State.COMPLETE
    return sim

static func export_cloud(cast: SurvivorContestantCatalog, output: String) -> void:
    DirAccess.make_dir_recursive_absolute(output)
    var gameplay: Array = []
    for entry: Dictionary in cast.all():
        var row := {}
        for key: String in SurvivorSeasonConfiguration.GAMEPLAY_FIELDS:
            row[key] = entry[key]
        gameplay.append(row)
    gameplay.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
    var canonical := JSON.stringify(gameplay, "", true)
    _write(output.path_join("approved_catalog.sql"), "insert into survivor_private.gameplay_catalogs(fingerprint,canonical) values ('%s','%s');" % [SurvivorSeasonConfiguration.fingerprint(cast), canonical.replace("'", "''")])
    var definitions := {}
    for id: String in MarooningSupplyCatalog.definitions():
        var d: Dictionary = MarooningSupplyCatalog.definitions()[id]
        definitions[id] = {"count":d.count, "quantity":d.quantity, "unit":d.unit, "mass_kg":d.mass_kg}
    _write(output.path_join("supply_definitions.json"), JSON.stringify(definitions, "", true))
    for count_value in [2, 3]:
        var configuration := config(cast, count_value)
        var sim := SeasonSimulation.new("a".repeat(32), ("b" if count_value == 2 else "c").repeat(32), 42)
        sim.configure(configuration, cast)
        for tick in 120:
            sim.advance("tonsai")
        var partner: String = sim.camps.tonsai.people.keys().filter(func(id: String) -> bool: return id != "1")[0]
        sim.camps.tonsai.respond("1", partner, "water", sim.tick, "d".repeat(32))
        _write(output.path_join("tribes-%d.json" % count_value), SaveCodec.encode(sim.snapshot(), 1, 1000))
        for winner: String in ["own", "rival", "unclaimed", "empty"]:
            sim = SeasonSimulation.new("a".repeat(32), ("b" if count_value == 2 else "c").repeat(32), 42)
            sim.configure(configuration, cast)
            var result := session(configuration, cast, winner == "empty", "unclaimed" if winner == "empty" else winner).result()
            sim.initialize_opening(SurvivorOpeningHandoff.build(result, configuration, cast))
            _write(output.path_join("opening-%d-%s.json" % [count_value, winner]), SaveCodec.encode(sim.snapshot(), 1, 1000))
    _write(output.path_join("technical.json"), SaveCodec.encode(SeasonSimulation.new("a".repeat(32), "e".repeat(32), 42).snapshot(), 1, 1000))

static func _write(path: String, value: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(value)
    file.close()
