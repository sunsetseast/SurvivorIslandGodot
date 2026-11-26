class_name SaveCodec
extends RefCounted

const SCHEMA := 2
const GAME_VERSION := "0.3.0"
const MAX_BYTES := 1_000_000
const MAX_REVISION := 4_000_000_000

static func encode(state: Dictionary, revision: int, stamp: int) -> String:
    var payload := JSON.stringify({"schema": SCHEMA, "game_version": GAME_VERSION,
        "save_revision": revision, "timestamp": stamp, "state": state}, "", state.get("ruleset") == SurvivorSeasonConfiguration.RULESET, true)
    return JSON.stringify({"payload": payload, "sha256": payload.sha256_text()})

static func decode(raw: String) -> Dictionary:
    var bad := {"status": "corrupt"}
    if raw.is_empty() or raw.length() > MAX_BYTES:
        return bad
    var wrapper: Variant = _parse(raw)
    if wrapper is not Dictionary or wrapper.get("payload") is not String:
        return bad
    var payload: String = wrapper.payload
    if wrapper.get("sha256") != payload.sha256_text():
        return bad
    var envelope: Variant = _parse(payload)
    if envelope is not Dictionary or not GameStateData.integer(envelope.get("schema"), 1, MAX_REVISION):
        return bad
    if envelope.schema > SCHEMA:
        return {"status": "unsupported"}
    var state: Variant = envelope.get("state")
    if state is not Dictionary or not GameStateData.integer(envelope.get("save_revision"), 1, MAX_REVISION) \
            or not GameStateData.integer(envelope.get("timestamp"), 1, 4_102_444_800) \
            or envelope.get("game_version") is not String:
        return bad
    if state.get("ruleset") not in [SeasonSimulation.RULESET, SurvivorSeasonConfiguration.RULESET] or state.get("ruleset_version") != 1:
        return {"status": "unsupported"}
    if envelope.schema == 1:
        # V1 stored camera/body pose without the dive flag.
        if state.get("pose") is Dictionary and not state.pose.is_empty():
            state.pose["underwater"] = false
        envelope.schema = SCHEMA
    if state.get("ruleset") == SurvivorSeasonConfiguration.RULESET:
        state = SurvivorContestantCatalog._integers(state)
        if state.get("configuration") is Dictionary and state.configuration.get("catalog") is String:
            state.configuration.catalog = SurvivorSeasonConfiguration.migrate_fingerprint(
                state.configuration.catalog, SurvivorContestantCatalog.new())
        envelope.state = state
    if not _valid_state(state):
        return bad
    envelope["status"] = "valid"
    return envelope

static func _valid_state(state: Dictionary) -> bool:
    var tick: Variant = state.get("tick")
    if not GameStateData.identity(state.get("season_id")) or not GameStateData.identity(state.get("player_id")) \
            or not GameStateData.int64_text(state.get("seed")) or not GameStateData.int64_text(state.get("rng_state")) \
            or not GameStateData.integer(tick, 0, SeasonSimulation.MAX_TICK) \
            or not GameStateData.integer(state.get("revision"), tick, MAX_REVISION):
        return false
    if state.get("ruleset") == SurvivorSeasonConfiguration.RULESET:
        return _valid_configurable(state)
    if state.get("controlled") != SeasonCatalog.CONTROLLED or state.get("phase") != "camp" \
            or state.get("day") != floori(float(tick) / SeasonSimulation.TICKS_PER_DAY) + 1 \
            or state.get("tribes") != SeasonCatalog.TRIBES:
        return false
    # The technical ruleset fixes membership. A swap/merge ruleset will validate
    # allowed membership and participation transitions against its own catalog.
    var roster := SeasonCatalog.roster(state.player_id)
    if state.get("roster") != roster:
        return false
    if state.get("pose") != {} and not GameStateData.pose(state.get("pose")):
        return false
    var world: Variant = state.get("world")
    if world is not Dictionary or world.size() != SeasonCatalog.LOCATIONS.size():
        return false
    for location: String in SeasonCatalog.LOCATIONS:
        if not _valid_camp(world.get(location), roster, location, int(tick)):
            return false
    return true

static func _valid_camp(camp: Variant, roster: Dictionary, location: String, tick: int) -> bool:
    if camp is not Dictionary or not GameStateData.integer(camp.get("arrivals"), 0, MAX_REVISION):
        return false
    var objects: Variant = camp.get("objects")
    if objects is not Dictionary or objects.get("fire") is not Dictionary or objects.fire.get("lit") is not bool:
        return false
    var people: Variant = camp.get("people")
    if people is not Dictionary or people.size() != roster.values().filter(func(p: Dictionary) -> bool: return p.location == location).size():
        return false
    var claimed := {}
    for id: String in roster:
        if roster[id].location != location:
            continue
        var person: Variant = people.get(id)
        if person is not Dictionary or not GameStateData.integer(person.get("deadline"), 0, tick + 112):
            return false
        var stage: Variant = person.get("stage")
        var activity: Variant = person.get("activity")
        if not stage in ["waiting", "travel", "occupied"] or activity is not String:
            return false
        if stage == "waiting":
            if not activity.is_empty():
                return false
        elif roster[id].controller == "human" or not CampSimulation.ACTIVITIES.has(activity) or claimed.has(activity):
            return false
        else:
            claimed[activity] = id
        var journal: Variant = person.get("journal")
        if journal is not Array or journal.size() > CampSimulation.MAX_RECORDS:
            return false
        var receipts := {}
        for record: Variant in journal:
            if record is not Dictionary or not GameStateData.identity(record.get("id")) \
                    or not GameStateData.integer(record.get("tick"), 0, tick) \
                    or record.get("with") == id or not people.has(record.get("with")) \
                    or not CampSimulation.TOPICS.has(record.get("topic")) or record.get("reply") is not String \
                    or record.reply.length() > 512 or receipts.has(record.id):
                return false
            receipts[record.id] = true
    return true

static func _parse(text: String) -> Variant:
    var parser := JSON.new()
    return parser.data if parser.parse(text) == OK else null

static func _valid_configurable(state: Dictionary) -> bool:
    var config: Variant = state.get("configuration")
    if config is not Dictionary or config.get("tribes") is not Array or not GameStateData.integer(config.get("selected"), 1, 18) or config.get("information") not in SurvivorNewSeasonSetup.INFORMATION_MODES or config.get("seed") != state.seed:
        return false
    var catalog := SurvivorContestantCatalog.new()
    if config.get("catalog") != SurvivorSeasonConfiguration.fingerprint(catalog):
        return false
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = int(config.selected)
    setup.information_mode = config.information
    var division := SurvivorSeasonConfiguration.new()
    division.count = config.tribes.size()
    division.method = str(config.get("method", ""))
    division.tribes = config.tribes
    division.seed_value = int(config.seed)
    if not division.validate(catalog, setup.selected_id) or division.configuration(catalog, setup) != config:
        return false
    var roster := SurvivorSeasonConfiguration.roster_for(config, catalog, state.player_id)
    if state.get("roster") != roster or state.get("controlled") != str(setup.selected_id) or state.get("phase") != "camp" or state.get("day") != floori(float(state.tick) / SeasonSimulation.TICKS_PER_DAY) + 1:
        return false
    var locations := {}
    for tribe: Dictionary in config.tribes:
        locations[tribe.id] = tribe.location
    if state.get("tribes") != locations or state.get("world") is not Dictionary or state.world.size() != locations.size() or state.get("pose") != {} and not GameStateData.pose(state.get("pose")):
        return false
    for location: String in locations.values():
        if not _valid_camp(state.world.get(location), roster, location, int(state.tick)):
            return false
    return true
