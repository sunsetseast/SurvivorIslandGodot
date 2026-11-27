class_name SurvivorOpeningHandoff
extends RefCounted
## Boundary validator/serializer only. SeasonSimulation owns the resulting state.
const REWARD_ID := "fishing-equipment-preview"
const MAX_SECONDS := 86400.0
const MAX_EVENTS := 2048
const ACTOR_COUNTS := ["strokes", "perfect", "good", "missed", "boardings", "departures", "unloaded_count"]
const ACTOR_AMOUNTS := ["swim_distance", "force_total", "impulse_total_ns", "impulse_delivered_ns", "impulse_cancelled_ns"]

static func instances() -> Dictionary:
    var result := {}
    for type: String in MarooningSupplyCatalog.definitions():
        var definition: Dictionary = MarooningSupplyCatalog.definitions()[type]
        for index in int(definition.count):
            result["%s-%02d" % [type, index]] = definition
    return result

static func item_record(definition: Dictionary, source := "marooning") -> Dictionary:
    return {"type":definition.id, "quantity":definition.quantity, "unit":definition.unit,
        "source":source, "definition_version":1}

static func reward_record() -> Dictionary:
    return {"type":"offshore_fishing_reward", "quantity":1, "unit":"package",
        "source":"offshore_reward", "definition_version":1}

static func build(result: Dictionary, config: Dictionary, catalog: SurvivorContestantCatalog) -> Dictionary:
    if result.get("version") != 2 or result.get("configuration") != config or result.get("selected") != config.get("selected") \
            or result.get("seed") != config.get("seed") or result.get("session_state") != MarooningSession.State.COMPLETE \
            or result.get("phase") != MarooningRace.Phase.ARRIVAL_COMPLETE or result.get("clock_owner") != "marooning_session" \
            or result.get("collection_closed") != true or result.get("collection_seconds") != 60.0 \
            or not GameStateData.number(result.get("elapsed"), 0, MAX_SECONDS):
        return {}
    var original := SurvivorSeasonConfiguration.roster_for(config, catalog, "")
    var contestants: Variant = result.get("contestants")
    var scramble: Variant = result.get("scramble")
    if contestants is not Dictionary or contestants.size() != 18 or scramble is not Dictionary \
            or scramble.get("configuration") != config or int(scramble.get("seed", -1)) != int(config.seed) \
            or scramble.get("secured") is not Dictionary or scramble.get("unsecured") is not Array \
            or scramble.get("contributions") is not Dictionary or result.get("rafts") is not Dictionary:
        return {}
    var history := {"version":1, "elapsed":result.elapsed, "supply_rng_state":str(result.get("supply_rng_state", "")),
        "travel_rng_state":str(result.get("rng_state", "")), "dispositions":{}, "contestants":{},
        "contributions":{}, "transport":{}, "reward":{}, "events":[], "recoveries":[],
        "witness_semantics":"proximity_candidates_only"}
    if str(scramble.get("rng_state", "")) != history.supply_rng_state:
        return {}
    var inventory := {}
    for tribe: Dictionary in config.tribes:
        inventory[tribe.id] = {}
        if scramble.secured.get(tribe.id) is not Array:
            return {}
        var raft: Variant = result.rafts.get(tribe.id)
        if raft is not Dictionary or raft.get("cargo_ids") is not Array or raft.get("delivered_ids") is not Dictionary:
            return {}
        history.transport[tribe.id] = {"arrived":raft.get("arrived"), "arrival_time":raft.get("arrival_time"),
            "launch_time":raft.get("launch_time"), "launch_reason":raft.get("launch_reason"),
            "state":raft.get("state"), "cargo_location":raft.get("cargo_location"),
            "delivered_ids":raft.delivered_ids.keys(), "resolution":"observed"}
        for item: Variant in scramble.secured[tribe.id]:
            if item is not Dictionary or item.get("tribe") != tribe.id or item.get("state") != MarooningScramble.State.SECURED \
                    or not _add_disposition(history, item):
                return {}
            inventory[tribe.id][item.id] = item_record(MarooningSupplyCatalog.definitions()[item.type])
        var expected: Array = inventory[tribe.id].keys()
        var actual: Array = raft.cargo_ids.duplicate()
        expected.sort()
        actual.sort()
        if expected != actual:
            return {}
        for delivered: Variant in raft.delivered_ids:
            if raft.delivered_ids[delivered] != true:
                return {}
        var all_arrived: bool = raft.get("arrived") == true
        for member: Variant in tribe.members:
            var actor: Variant = contestants.get(int(member))
            var id := str(int(member))
            if actor is not Dictionary or actor.get("tribe") != tribe.id or actor.get("attributes") != original[id].attributes:
                return {}
            all_arrived = all_arrived and actor.get("arrived") == true
            var row := {"tribe":tribe.id, "arrived":actor.get("arrived"), "recovered":actor.get("recovered"),
                "fatigue":actor.get("fatigue"), "arrival_time":actor.get("arrival_time", -1.0),
                "left_deck_at":actor.get("left_deck_at", -1.0)}
            for key: String in ACTOR_COUNTS + ACTOR_AMOUNTS:
                row[key] = actor.get(key)
            history.contestants[id] = row
            if scramble.contributions.get(int(member)) is not Dictionary:
                return {}
            history.contributions[id] = scramble.contributions[int(member)].duplicate(true)
        if not all_arrived or raft.delivered_ids.size() != expected.size():
            history.transport[tribe.id].resolution = "abstract_transport"
        if int(config.selected) in tribe.members and (history.transport[tribe.id].resolution != "observed" \
                or raft.get("state") != "regrouped" or raft.get("cargo_location") != "shore"):
            return {}
    if scramble.secured.size() != inventory.size() or result.rafts.size() != inventory.size():
        return {}
    for item: Variant in scramble.unsecured:
        if item is not Dictionary or item.get("state") == MarooningScramble.State.SECURED or not _add_disposition(history, item):
            return {}
    var reward: Variant = result.get("reward")
    if reward is not Dictionary:
        return {}
    for key: String in ["id", "status", "tribe", "actor", "time", "method", "mass_kg", "carrier", "secured", "location"]:
        history.reward[key] = reward.get(key)
    history.reward.actor = _id_text(reward.get("actor"))
    history.reward.carrier = _id_text(reward.get("carrier"))
    if reward.get("status") == "claimed" and reward.get("secured") == true and inventory.has(reward.get("tribe")):
        inventory[reward.tribe][REWARD_ID] = reward_record()
    if result.get("events") is not Array or result.events.size() > 8192 or result.get("recoveries") is not Array:
        return {}
    for event: Variant in result.events:
        if event is not Dictionary or event.get("action") is not String:
            return {}
        # Navigation repaths are transient technical diagnostics, not social facts.
        if event.get("source") == "navigation" and event.action == "deck_repath":
            continue
        # Stroke totals/grades and impulse contributions above retain repetitive evidence.
        if event.action.begins_with("stroke_"):
            continue
        var row := {"source":event.get("source"), "at":event.get("elapsed"), "actor":_id_text(event.get("actor")),
            "action":event.action, "witness_candidates":[]}
        if event.get("nearby_witnesses") is not Array:
            return {}
        for witness: Variant in event.nearby_witnesses:
            row.witness_candidates.append(_id_text(witness))
        if event.source == "supplies":
            row.merge({"instance":event.get("instance"), "outcome":event.get("outcome"), "victim":_id_text(event.get("victim", 0))})
        history.events.append(row)
    for recovery: Variant in result.recoveries:
        if recovery is not Dictionary or recovery.get("from") is not Vector3 or recovery.get("to") is not Vector3:
            return {}
        var row := {"actor":_id_text(recovery.get("actor")), "at":recovery.get("elapsed"), "reason":recovery.get("reason"),
            "attempts":recovery.get("attempts"), "from":_point(recovery.from), "to":_point(recovery.to),
            "ordinary_cargo_set_down":recovery.get("ordinary_cargo_set_down"), "secured_batch":recovery.get("secured_batch"),
            "reward_carrier":recovery.get("reward_carrier"), "objective_awarded":recovery.get("objective_awarded")}
        history.recoveries.append(row)
    var packet := {"inventory_version":1, "tribal_inventory":inventory, "opening_history":history,
        "initialization":{"source":"marooning-v2", "day":1, "tick":0, "first_impressions_complete":false, "rng_stream":"camp-v1"}}
    packet = SurvivorContestantCatalog._integers(packet)
    return packet if valid(packet, config) else {}

static func _id_text(value: Variant) -> String:
    return str(int(value)) if GameStateData.integer(value, 0, 18) else "invalid"

static func _point(value: Vector3) -> Array:
    return [value.x, value.y, value.z]

static func _add_disposition(history: Dictionary, item: Dictionary) -> bool:
    var definition: Dictionary = instances().get(item.get("id"), {})
    if definition.is_empty() or history.dispositions.has(item.id) or item.get("type") != definition.id \
            or item.get("quantity") != definition.quantity or item.get("mass_kg") != definition.mass_kg \
            or item.get("unit") != definition.unit or item.get("definition_version") != 1:
        return false
    history.dispositions[item.id] = {"type":item.type, "state":item.get("state"), "tribe":item.get("tribe"),
        "actor":_id_text(item.get("actor")), "quantity":item.quantity, "unit":item.unit, "mass_kg":item.mass_kg,
        "definition_version":1, "location":item.get("location", "ship"), "secured_at":item.get("secured_at", -1.0),
        "unloader":_id_text(item.get("unloader", 0))}
    return true

static func valid(packet: Dictionary, config: Dictionary) -> bool:
    if packet.get("inventory_version") != 1 or packet.get("tribal_inventory") is not Dictionary \
            or packet.get("opening_history") is not Dictionary or packet.get("initialization") != {"source":"marooning-v2", "day":1, "tick":0, "first_impressions_complete":false, "rng_stream":"camp-v1"}:
        return false
    var h: Dictionary = packet.opening_history
    if h.keys().size() != 12 or h.get("version") != 1 or h.get("witness_semantics") != "proximity_candidates_only" \
            or not GameStateData.number(h.get("elapsed"), 0, MAX_SECONDS) \
            or not GameStateData.int64_text(h.get("supply_rng_state")) or not GameStateData.int64_text(h.get("travel_rng_state")):
        return false
    for key: String in ["dispositions", "contestants", "contributions", "transport", "reward"]:
        if h.get(key) is not Dictionary:
            return false
    if h.dispositions.size() != 50 or h.contestants.size() != 18 or h.contributions.size() != 18 \
            or h.transport.size() != config.tribes.size() or packet.tribal_inventory.size() != config.tribes.size():
        return false
    var membership := {}
    var expected := {}
    var own := ""
    for tribe: Dictionary in config.tribes:
        expected[tribe.id] = {}
        for member: Variant in tribe.members:
            membership[str(int(member))] = tribe.id
        if int(config.selected) in tribe.members:
            own = tribe.id
    var definitions := instances()
    for id: String in definitions:
        var row: Variant = h.dispositions.get(id)
        var d: Dictionary = definitions[id]
        if row is not Dictionary or row.size() != 11 or row.get("type") != d.id or row.get("quantity") != d.quantity \
                or row.get("unit") != d.unit or row.get("mass_kg") != d.mass_kg or row.get("definition_version") != 1 \
                or not GameStateData.integer(row.get("state"), 0, 5) or not _actor(row.get("actor"), membership, true) \
                or not _actor(row.get("unloader"), membership, true) or row.get("location") not in ["ship", "loading", "raft", "carried", "shore"] \
                or not GameStateData.number(row.get("secured_at"), -1, h.elapsed):
            return false
        if row.state == MarooningScramble.State.SECURED:
            if not expected.has(row.get("tribe")) or row.actor != "0" or row.secured_at < 0 \
                    or row.unloader != "0" and membership[row.unloader] != row.tribe:
                return false
            if row.tribe == own and row.location != "shore":
                return false
            expected[row.tribe][id] = item_record(d)
        elif row.get("tribe") != "" or (row.state == MarooningScramble.State.CARRIED) != (row.actor != "0"):
            return false
    for id: String in membership:
        var row: Variant = h.contestants.get(id)
        var contributions: Variant = h.contributions.get(id)
        if row is not Dictionary or row.size() != 18 or row.get("tribe") != membership[id] \
                or row.get("arrived") is not bool or row.get("recovered") is not bool \
                or not GameStateData.number(row.get("fatigue"), 0, 1) \
                or not GameStateData.number(row.get("arrival_time"), -1, h.elapsed) \
                or not GameStateData.number(row.get("left_deck_at"), -1, h.elapsed) \
                or row.arrived != (row.arrival_time >= 0) or membership[id] == own and not row.arrived \
                or contributions is not Dictionary or contributions.size() > 64:
            return false
        for key: String in ACTOR_COUNTS:
            if not GameStateData.integer(row.get(key), 0, 1000000):
                return false
        for key: String in ACTOR_AMOUNTS:
            if not GameStateData.number(row.get(key), 0, 1e12):
                return false
        for key: Variant in contributions:
            if key is not String or key.length() > 64 or not GameStateData.integer(contributions[key], 0, 1000000):
                return false
    for tribe: Dictionary in config.tribes:
        var row: Variant = h.transport.get(tribe.id)
        if row is not Dictionary or row.size() != 8 or row.get("arrived") is not bool \
                or not GameStateData.number(row.get("arrival_time"), -1, h.elapsed) \
                or not GameStateData.number(row.get("launch_time"), -1, h.elapsed) \
                or row.get("launch_reason") not in ["", "collection_closed", "crew_encouraged", "crew_ready"] \
                or row.arrived != (row.arrival_time >= 0) or row.get("delivered_ids") is not Array \
                or row.get("resolution") not in ["observed", "abstract_transport"] \
                or row.get("state") not in ["moored", "underway", "grounded", "regrouped"] \
                or row.get("cargo_location") not in ["raft", "shore"] \
                or tribe.id == own and (row.state != "regrouped" or row.cargo_location != "shore"):
            return false
        var delivered := {}
        for id: Variant in row.delivered_ids:
            if id is not String or not expected[tribe.id].has(id) or delivered.has(id) or h.dispositions[id].location != "shore":
                return false
            delivered[id] = true
        var observed: bool = row.arrived and delivered.size() == expected[tribe.id].size()
        for id: Variant in tribe.members:
            observed = observed and h.contestants[str(int(id))].arrived
        if (row.resolution == "observed") != observed or tribe.id == own and not observed:
            return false
    var reward: Dictionary = h.reward
    if reward.size() != 10 or reward.get("id") != REWARD_ID or reward.get("status") not in ["claimed", "unclaimed"] \
            or reward.get("mass_kg") != 8.0 or not GameStateData.number(reward.get("time"), 0, h.elapsed) \
            or reward.get("secured") is not bool or not _actor(reward.get("actor"), membership, true) \
            or not _actor(reward.get("carrier"), membership, true):
        return false
    if reward.status == "unclaimed":
        if reward.tribe != "" or reward.actor != "0" or reward.carrier != "0" or reward.secured or reward.location != "unclaimed" or reward.method != "":
            return false
    else:
        if not expected.has(reward.get("tribe")) or reward.actor == "0" or membership[reward.actor] != reward.tribe \
                or reward.get("method") not in ["raft", "swim"] or reward.get("location") not in ["raft", "carried", "shore"] \
                or reward.carrier != "0" and membership[reward.carrier] != reward.tribe \
                or (reward.location == "carried") != (reward.carrier != "0") \
                or not reward.secured and reward.location != "carried" \
                or reward.tribe == own and (not reward.secured or reward.location != "shore"):
            return false
        if reward.secured:
            expected[reward.tribe][REWARD_ID] = reward_record()
    # Remaining quantities may only decrease from original acquisitions. No gameplay
    # changes them in this phase; history retains original quantities and physical mass.
    for tribe: String in expected:
        var items: Variant = packet.tribal_inventory.get(tribe)
        if items is not Dictionary or items.keys().size() != expected[tribe].size():
            return false
        for id: String in expected[tribe]:
            var item: Variant = items.get(id)
            var acquisition: Dictionary = expected[tribe][id]
            if item is not Dictionary or item.size() != acquisition.size() or not GameStateData.number(item.get("quantity"), 0, acquisition.quantity):
                return false
            var check_item: Dictionary = item.duplicate()
            check_item.quantity = acquisition.quantity
            if check_item != acquisition:
                return false
    if h.get("events") is not Array or h.events.size() > MAX_EVENTS or h.get("recoveries") is not Array or h.recoveries.size() > 128:
        return false
    var previous := 0.0
    for event: Variant in h.events:
        if event is not Dictionary or event.get("source") not in ["supplies", "travel"] \
                or event.size() != (8 if event.source == "supplies" else 5) \
                or not GameStateData.number(event.get("at"), previous, h.elapsed) or not _actor(event.get("actor"), membership) \
                or event.get("action") is not String or event.action.is_empty() or event.action.length() > 64 \
                or event.get("witness_candidates") is not Array or event.witness_candidates.size() > 17:
            return false
        previous = float(event.at)
        var seen := {}
        for witness: Variant in event.witness_candidates:
            if not _actor(witness, membership) or witness == event.actor or seen.has(witness):
                return false
            seen[witness] = true
        if event.source == "supplies" and (not definitions.has(event.get("instance")) \
                or event.get("outcome") is not String or event.outcome.length() > 64 or not _actor(event.get("victim"), membership, true)):
            return false
    for recovery: Variant in h.recoveries:
        if recovery is not Dictionary or recovery.size() != 10 or not _actor(recovery.get("actor"), membership) \
                or not GameStateData.number(recovery.get("at"), 0, h.elapsed) or recovery.get("reason") is not String \
                or recovery.reason.length() > 128 or not GameStateData.integer(recovery.get("attempts"), 0, 10000) \
                or recovery.get("objective_awarded") != false or recovery.get("reward_carrier") is not bool \
                or recovery.get("ordinary_cargo_set_down") is not String or recovery.get("secured_batch") is not Array:
            return false
        if recovery.ordinary_cargo_set_down != "" and not definitions.has(recovery.ordinary_cargo_set_down):
            return false
        for id: Variant in recovery.secured_batch:
            if not definitions.has(id) or h.dispositions[id].tribe != membership[recovery.actor]:
                return false
        for key: String in ["from", "to"]:
            if recovery.get(key) is not Array or recovery[key].size() != 3:
                return false
            for coordinate: Variant in recovery[key]:
                if not GameStateData.number(coordinate, -10000, 10000):
                    return false
    return true

static func _actor(value: Variant, membership: Dictionary, zero := false) -> bool:
    return value is String and (membership.has(value) or zero and value == "0")

static func summary(items: Dictionary) -> String:
    var totals := {}
    var definitions := MarooningSupplyCatalog.definitions()
    for item: Dictionary in items.values():
        totals[item.type] = float(totals.get(item.type, 0)) + float(item.quantity)
    var groups := {"Food":[], "Water":[], "Equipment":[], "Construction materials":[]}
    for type: String in definitions:
        if totals.has(type):
            var category: String = definitions[type].category
            var group := "Food" if category == "food" else ("Water" if category == "water" else ("Construction materials" if category in ["shelter", "fire"] else "Equipment"))
            groups[group].append("%s · %s %s" % [definitions[type].name, str(totals[type]), definitions[type].unit])
    if totals.has("offshore_fishing_reward"):
        groups.Equipment.append("Offshore fishing reward · 1 package")
    var lines: PackedStringArray = []
    for group: String in groups:
        if not groups[group].is_empty():
            lines.append(group + "\n" + "\n".join(groups[group]))
    return "No supplies secured" if lines.is_empty() else "\n\n".join(lines)
