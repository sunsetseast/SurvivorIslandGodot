class_name SeasonSimulation
extends RefCounted
## Scene-free rule owner. Local and future dedicated hosts supply trusted physical observations.

const RULESET := "technical-season"
const RULESET_VERSION := 1
const TICK_SECONDS := .25
const TICKS_PER_DAY := 2400
const MAX_TICK := 1_000_000_000
const REACH := 2.65

var configuration: Dictionary = {}
var season_id: String
var player_id: String
var roster: Dictionary
var camps: Dictionary[String, CampSimulation] = {}
var tick := 0
var revision := 0
var pose: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _receipts: Dictionary = {}

func _init(owner_id: String, season: String, seed_value: int, owners: Dictionary = {}) -> void:
    player_id = owner_id
    season_id = season
    roster = SeasonCatalog.roster(owner_id, owners)
    rng.seed = seed_value
    for location: String in SeasonCatalog.LOCATIONS:
        camps[location] = CampSimulation.new()
    for id: String in roster:
        camps[roster[id].location].add(id, SeasonCatalog.FIRST_ACTIVITIES.get(id, "") if roster[id].controller == "ai" else "")

func advance(physical_location: String) -> void:
    advance_locations([physical_location])

func advance_locations(physical_locations: Array[String]) -> void:
    if tick >= MAX_TICK:
        return
    tick += 1
    revision += 1
    for id: String in roster:
        var person: Dictionary = roster[id]
        if person.controller == "ai" and person.status == "active":
            camps[person.location].schedule(id, tick, physical_locations.has(person.location), rng)

func observe_travel(location: String, id: String, activity: String, arrived: bool) -> bool:
    var person: Dictionary = roster.get(id, {})
    if person.get("controller") != "ai" or person.get("location") != location or person.get("status") != "active":
        return false
    var camp := camps[location]
    var changed := camp.arrived(id, activity, tick, rng) if arrived else camp.travel_failed(id, activity, tick)
    revision += int(changed)
    return changed

func command(principal: String, request: Dictionary, observation: Dictionary) -> Dictionary:
    var actor: Variant = request.get("actor")
    var id: Variant = request.get("id")
    if actor is not String or actor.is_empty() or actor != contestant_for(principal):
        return _result(id, false, "not_owned")
    if id is not String or not GameStateData.identity(id):
        return _result("", false, "invalid_id")
    var receipt_key: String = actor + ":" + id
    if _receipts.has(receipt_key):
        return _receipts[receipt_key].duplicate(true)
    var target: Variant = request.get("target")
    var camp := camps[roster[actor].location]
    if target is not String or target == actor or not camp.people.has(target) or roster[target].status != "active" \
            or roster[target].controller != "ai":
        return _result(id, false, "invalid_target")
    var kind: Variant = request.get("kind")
    var event := {}
    match kind:
        "talk.begin":
            if camp.conversations.has(actor) or camp.conversations.values().has(target) or observation.get("target") != target \
                    or observation.get("location") != roster[actor].location \
                    or not GameStateData.number(observation.get("distance"), 0, REACH) \
                    or observation.get("accessible") != true:
                return _result(id, false, "unavailable")
            camp.conversations[actor] = target
            event = {"type": "conversation_opened", "with": target}
        "talk.respond":
            var topic: Variant = request.get("topic")
            if camp.conversations.get(actor) != target or topic is not String or not CampSimulation.TOPICS.has(topic):
                return _result(id, false, "invalid_conversation_action")
            for record: Dictionary in camp.people[actor].journal:
                if record.id == id:
                    return _result(id, true, "", {"type": "conversation_reply", "with": record.with, "reply": record.reply})
            var reply := camp.respond(actor, target, topic, tick, id)
            event = {"type": "conversation_reply", "with": target, "reply": reply}
        "talk.end":
            if camp.conversations.get(actor) != target:
                return _result(id, false, "invalid_conversation_action")
            camp.conversations.erase(actor)
            event = {"type": "conversation_closed", "with": target}
        _:
            return _result(id, false, "unknown_command")
    revision += 1
    var result := _result(id, true, "", event)
    _receipts[receipt_key] = result.duplicate(true)
    if _receipts.size() > CampSimulation.MAX_RECORDS:
        _receipts.erase(_receipts.keys().front())
    return result

func _result(id: Variant, ok: bool, reason: String, event := {}) -> Dictionary:
    return {"id": str(id), "ok": ok, "reason": reason, "revision": revision, "event": event}

func project(principal: String, location: String, include_knowledge := true) -> Dictionary:
    var actor := contestant_for(principal)
    if actor.is_empty() or location != roster[actor].location:
        return {}
    var cast := {}
    var camp := camps[location]
    for id: String in camp.people:
        var person: Dictionary = camp.people[id]
        cast[id] = {"name": roster[id].name, "activity": person.activity, "stage": person.stage}
    return {"season_id": season_id, "revision": revision, "tick": tick, "day": day(),
        "phase": "camp", "cast": cast, "objects": camp.objects.duplicate(true),
        "controlled": actor, "pose": pose.duplicate(true),
        "knowledge": camp.people[actor].journal.duplicate(true) if include_knowledge else []}

func contestant_for(principal: String) -> String:
    if not principal.is_empty():
        for id: String in roster:
            var person: Dictionary = roster[id]
            if person.controller == "human" and person.owner == principal and person.status == "active":
                return id
    return ""

func day() -> int:
    return floori(float(tick) / TICKS_PER_DAY) + 1

func snapshot() -> Dictionary:
    var world := {}
    for location: String in camps:
        world[location] = camps[location].snapshot()
    var result := {"season_id": season_id, "player_id": player_id, "ruleset": RULESET if configuration.is_empty() else SurvivorSeasonConfiguration.RULESET,
        "ruleset_version": RULESET_VERSION, "revision": revision, "tick": tick, "day": day(),
        "phase": "camp", "seed": str(rng.seed), "rng_state": str(rng.state),
        "controlled": contestant_for(player_id), "roster": roster.duplicate(true),
        "tribes": tribe_locations(), "world": world, "pose": pose.duplicate(true)}
    if not configuration.is_empty():
        result["configuration"] = configuration.duplicate(true)
    return result

static func restore(data: Dictionary) -> SeasonSimulation:
    var sim := SeasonSimulation.new(data.player_id, data.season_id, int(data.seed))
    if data.get("ruleset") == SurvivorSeasonConfiguration.RULESET:
        sim.configure(data.configuration, SurvivorContestantCatalog.new())
    # Keep the ruleset's canonical roster order across JSON encoders and migrations.
    for id: String in sim.roster:
        sim.roster[id] = data.roster[id].duplicate(true)
    sim.tick = int(data.tick)
    sim.revision = int(data.revision)
    sim.pose = data.pose.duplicate(true)
    sim.rng.state = int(data.rng_state)
    for location: String in sim.camps:
        var saved: Dictionary = data.world[location].duplicate(true)
        if not sim.configuration.is_empty():
            var ordered := {}
            for id: String in sim.camps[location].people:
                ordered[id] = saved.people[id]
            saved.people = ordered
        sim.camps[location].restore(saved)
    return sim

func tribe_locations() -> Dictionary:
    if configuration.is_empty():
        return SeasonCatalog.TRIBES.duplicate()
    var result := {}
    for tribe: Dictionary in configuration.tribes:
        result[tribe.id] = tribe.location
    return result

func configure(config: Dictionary, catalog: SurvivorContestantCatalog) -> void:
    configuration = config.duplicate(true)
    roster = SurvivorSeasonConfiguration.roster_for(config, catalog, player_id)
    camps.clear()
    for tribe: Dictionary in config.tribes:
        camps[tribe.location] = CampSimulation.new()
    for id: String in roster:
        camps[roster[id].location].add(id, "")
