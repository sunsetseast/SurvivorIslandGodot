extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", message)
func _initialize() -> void:
    var cast := OpeningFixture.catalog()
    var output := OS.get_environment("OPENING_FIXTURE_DIR")
    if not output.is_empty():
        OpeningFixture.export_cloud(cast, output)
    for count_value in [2, 3]:
        var config := OpeningFixture.config(cast, count_value)
        for winner: String in ["own", "rival", "unclaimed"]:
            var marooning := OpeningFixture.session(config, cast, false, winner)
            var handoff := marooning.result()
            var packet := SurvivorOpeningHandoff.build(handoff, config, cast)
            check(not packet.is_empty(), "Valid production v2 handoff %d/%s" % [count_value, winner])
            if packet.is_empty():
                continue
            check(packet.opening_history.dispositions.size() == 50, "All fifty original dispositions")
            var own: String = marooning.race.actors[1].tribe
            check(packet.tribal_inventory[own]["rice-00"].quantity == 20 and packet.tribal_inventory[own]["water-00"].quantity == 10, "Exact catalog quantities")
            check(packet.tribal_inventory[own].has(SurvivorOpeningHandoff.REWARD_ID) == (winner == "own"), "Exclusive reward ownership")
            check(packet.opening_history.transport[own].resolution == "observed", "Own physical arrival required")
            var sim := SeasonSimulation.new("a".repeat(32), "b".repeat(32), 42)
            sim.configure(config, cast)
            var canonical := sim.roster.duplicate(true)
            check(sim.initialize_opening(packet) and not sim.initialize_opening(packet), "One-time initialization")
            check(sim.roster == canonical and sim.roster.size() == 18, "Exact immutable identities and membership")
            check(sim.tick == 0 and sim.day() == 1 and not sim.camps.tonsai.objects.fire.lit, "Day 1 tick 0, no fire or shelter benefits")
            check(sim.project(sim.player_id, "tonsai").supplies == packet.tribal_inventory[own], "Projection contains only own supplies")
            var raw := SaveCodec.encode(sim.snapshot(), 1, 100)
            var decoded := SaveCodec.decode(raw)
            check(decoded.status == "valid", "V2 codec validation")
            if decoded.status == "valid":
                var restored := SeasonSimulation.restore(decoded.state)
                check(restored.snapshot() == sim.snapshot(), "Exact restore including int64 RNG")
                sim.advance("")
                restored.advance("")
                check(restored.snapshot() == sim.snapshot(), "Deterministic camp RNG continuation")
            var invalid := handoff.duplicate(true)
            invalid.scramble.unsecured.append(invalid.scramble.unsecured[0])
            check(SurvivorOpeningHandoff.build(invalid, config, cast).is_empty(), "Duplicate disposition rejected")
            invalid = handoff.duplicate(true)
            invalid.session_state = MarooningSession.State.ACTIVE
            check(SurvivorOpeningHandoff.build(invalid, config, cast).is_empty(), "Incomplete rejected")
            invalid = handoff.duplicate(true)
            invalid.contestants[1].attributes.strength += 1
            check(SurvivorOpeningHandoff.build(invalid, config, cast).is_empty(), "Changed attributes rejected")
            invalid = handoff.duplicate(true)
            invalid.rafts[own].delivered_ids.clear()
            check(SurvivorOpeningHandoff.build(invalid, config, cast).is_empty(), "Undelivered selected cargo rejected")
            var store := LocalDataStore.new("opening-test-" + GameStateData.new_id())
            var saves := LocalSaveProvider.new(store)
            check(saves.write(1, sim.snapshot(), 0).status == "valid", "Verified initial checkpoint")
            check(saves.write(1, sim.snapshot(), 0).status == "conflict", "Repeated create protected")
            var downgrade := sim.snapshot()
            downgrade.ruleset_version = 1
            for key: String in ["inventory_version", "tribal_inventory", "opening_history", "initialization"]:
                downgrade.erase(key)
            check(saves.write(1, downgrade, 1).status == "conflict", "Old client downgrade protected")
            check(SaveCodec.decode(SaveCodec.encode(downgrade, 2, 100)).status == "valid", "Version 1 independently remains valid")
            saves.erase(1)
        var empty := OpeningFixture.session(config, cast, true, "unclaimed")
        var empty_packet := SurvivorOpeningHandoff.build(empty.result(), config, cast)
        check(not empty_packet.is_empty() and empty_packet.tribal_inventory.values().all(func(items: Dictionary) -> bool: return items.is_empty()), "Empty inventory legitimate")
    print("Permanent opening: ", failures, " failures")
    quit(1 if failures else 0)
