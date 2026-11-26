extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", label)
func _initialize() -> void:
    var catalog := SurvivorContestantCatalog.new()
    check(catalog.available, "Private approved catalog required")
    if not catalog.available:
        quit(1)
        return
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = 18
    var division := SurvivorSeasonConfiguration.new()
    for method: String in ["Random", "Balanced", "Manual", "Brains / Brawn / Beauty", "Battle of the Sexes"]:
        for count_value in [2, 3]:
            for seed_value in [1, 7, 42, 12345]:
                division.method = method
                division.count = count_value
                division.seed_value = seed_value
                division.assign(catalog)
                check(division.validate(catalog, 18), "Membership " + method)
                if method == "Balanced":
                    var males: Array = []
                    for tribe: Dictionary in division.tribes:
                        var number := 0
                        for id: int in tribe.members:
                            number += int(catalog.get_by_id(id).gender == "male")
                        males.append(number)
                    check(males.max() - males.min() <= 1, "Balanced gender representation")
                var config := division.configuration(catalog, setup)
                division.assign(catalog)
                check(config == division.configuration(catalog, setup), "Deterministic assignment")
                var sim := SeasonSimulation.new("a".repeat(32), "b".repeat(32), seed_value)
                sim.configure(config, catalog)
                check(sim.contestant_for("a".repeat(32)) == "18", "Actual ownership")
                check(sim.project("a".repeat(32), "tonsai").cast.size() == 18 / division.count, "Playable tribe capacity")
                for entry: Dictionary in catalog.all():
                    check(sim.roster[str(int(entry.id))].attributes == entry.attributes, "Exact attributes")
                    check(sim.roster[str(int(entry.id))].state == entry.defaults, "Exact defaults")
                for tick in 120:
                    sim.advance("tonsai")
                var state := sim.snapshot()
                var decoded := SaveCodec.decode(SaveCodec.encode(state, 1, 100))
                check(decoded.status == "valid", "Save " + method)
                if decoded.status == "valid":
                    var restored := SeasonSimulation.restore(decoded.state)
                    check(restored.snapshot() == state, "Canonical restore")
                    check(SaveCodec.encode(restored.snapshot(), 1, 100) == SaveCodec.encode(state, 1, 100), "Canonical serialization")
                    sim.advance("tonsai")
                    restored.advance("tonsai")
                    check(sim.snapshot() == restored.snapshot(), "RNG continuation")
                division.tribes[0].members[0] = division.tribes[1].members[0]
                check(not division.validate(catalog, 18), "Reject duplicate")
    division.method = "Manual"
    division.assign(catalog)
    var before: int = division.tribes[0].members[0]
    division._swap(0, 0, 1, 0)
    check(division.tribes[1].members[0] == before and division.validate(catalog, 18), "Manual swap")
    var technical := SeasonSimulation.new("a".repeat(32), "c".repeat(32), 1)
    check(SaveCodec.decode(SaveCodec.encode(technical.snapshot(), 1, 100)).status == "valid", "Technical compatibility")
    var cloud := SurvivorCloudSaveService.new(null)
    check(not cloud.mark_guest_import(1, {"ruleset":SurvivorSeasonConfiguration.RULESET}), "No configurable account import")
    cloud.free()
    print("PHASE 4C failures: ", failures)
    quit(1 if failures else 0)
