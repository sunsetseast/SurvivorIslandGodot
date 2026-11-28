extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAIL: ", label)

func saved(sim: SeasonSimulation) -> SeasonSimulation:
    var decoded := SaveCodec.decode(SaveCodec.encode(sim.snapshot(), 1, 100))
    check(decoded.status == "valid", "v3 codec accepts current state")
    return SeasonSimulation.restore(decoded.state) if decoded.status == "valid" else null

func _initialize() -> void:
    var cast := OpeningFixture.catalog()
    for count_value in [2, 3]:
        var config := OpeningFixture.config(cast, count_value)
        var packet := SurvivorOpeningHandoff.build(OpeningFixture.session(config, cast).result(), config, cast)
        var sim := SeasonSimulation.new("a".repeat(32), "b".repeat(32), 42)
        sim.configure(config, cast)
        check(sim.initialize_opening(packet), "initialize Living Camp")
        check(sim.conditions.size() == 18 and sim.ruleset_version == 3, "all eighteen conditions")
        var own: String = sim.roster["1"].tribe
        var energy: int = sim.conditions["1"].energy
        check(energy == LivingCampRules.initial(float(packet.opening_history.contestants["1"].fatigue)).energy, "recorded fatigue initializes once")
        check(sim.opening.tribal_inventory[own]["water-00"].quantity == 10000, "integer millilitres migration")
        var restored := saved(sim)
        check(restored != null and restored.snapshot() == sim.snapshot(), "exact v3 round trip")
        if restored == null: continue
        sim.upgrade_living()
        check(sim.conditions["1"].energy == energy, "upgrade never reapplies fatigue")
        var session := LocalGameSession.new(sim, sim.player_id)
        session.set_paused(true)
        session.step(20)
        session.set_paused(false)
        session.step(20)
        check(sim.tick == 0, "pause and suspension delta discarded")
        for frame in 25:
            session.set_paused(false)
            session.step(.01)
        check(sim.calendar_seconds == 30 and sim.tick == 1, "fixed clock acceleration")
        for id: String in sim.conditions:
            check(sim.conditions[id].nutrition == 85 * LivingCampRules.SCALE - 60, "equivalent human NPC depletion")
        var cal := LivingCampRules.calendar(79200)
        check(cal.day == 2 and cal.seconds == 21600 and cal.period == "dawn", "06:00 day boundary")
        check(LivingCampRules.calendar(0).seconds == 28800 and LivingCampRules.calendar(39600).period == "night", "08:00 start and night")
        var tribe_inventory: Dictionary = sim.opening.tribal_inventory[own]
        var original := tribe_inventory.duplicate(true)
        var seq := int(sim.transaction_state.sequence) + 1
        check(not sim.resource_transaction("1", own, seq, "consume", {"instance":"water-00", "quantity":10001}), "insufficient rejects atomically")
        check(tribe_inventory == original, "rejected transaction unchanged")
        check(not sim.resource_transaction("1", own, seq, "consume", {"instance":"water-00", "quantity":-1}), "negative rejected")
        check(sim.resource_transaction("1", own, seq, "consume", {"instance":"water-00", "quantity":10000}), "zero remaining legitimate")
        check(not sim.resource_transaction("1", own, seq, "consume", {"instance":"water-00", "quantity":1}), "duplicate execution rejected")
        sim.conditions["1"].hydration = 1000
        check(sim.recover("1", "water", true) and sim.conditions["1"].hydration > 1000, "empty tribe well fallback")
        check(not sim.recover("1", "rice"), "uncooked rice forbidden")
        sim.conditions["1"].nutrition = 1000
        check(sim.recover("1", "coconut") and tribe_inventory["coconut-00"].quantity == 2, "food recovers with real cost")
        var rival := ""
        for tribe: String in sim.tribe_locations():
            if tribe != own: rival = tribe
        var rival_before: Dictionary = sim.opening.tribal_inventory[rival].duplicate(true)
        check(not sim.resource_transaction("1", rival, int(sim.transaction_state.sequence) + 1, "acquire", {"type":"water", "quantity":10, "source":"camp_gameplay"}), "cross tribe denied")
        check(sim.opening.tribal_inventory[rival] == rival_before, "rival resource isolation")
        check(sim.resource_transaction("1", own, int(sim.transaction_state.sequence) + 1, "acquire", {"type":"water", "quantity":500, "source":"camp_gameplay"}), "post-marooning acquisition")
        check(not sim.resource_transaction("1", own, int(sim.transaction_state.sequence) + 1, "acquire", {"type":"invalid", "quantity":500, "source":"camp_gameplay"}), "unknown resource rejected")
        var camp: CampSimulation = sim.camps.tonsai
        var members: Array = camp.people.keys()
        for id: String in members: camp.interrupt(id, sim.tick)
        check(camp.start("1", "shelter", sim.tick, sim.rng), "human starts trusted rest")
        check(camp.start(str(members[1]), "shelter", sim.tick, sim.rng), "multi person capacity")
        sim.conditions["1"].energy = 10000
        sim.advance("tonsai")
        check(sim.conditions["1"].energy == 10360, "rest recovery replaces awake depletion")
        camp.interrupt(str(members[1]), sim.tick)
        check(camp.reservations.shelter.has("1") and not camp.reservations.shelter.has(str(members[1])), "equal activity records release correct participant")
        camp.interrupt("1", sim.tick)
        check(not camp.reservations.get("shelter", []).has("1"), "interrupt releases own slot")
        var traveler: String = members[2]
        camp._reserve(traveler, "spring", sim.tick)
        var hydration: int = sim.conditions[traveler].hydration
        for step in 30: sim.advance("tonsai")
        check(camp.people[traveler].stage == "travel" and sim.conditions[traveler].hydration < hydration, "physical selection cannot perform or recover")
        var traveling_save := saved(sim)
        check(traveling_save != null and traveling_save.snapshot() == sim.snapshot(), "travel and interruption saved")
        check(sim.observe_travel("tonsai", traveler, "spring", true), "trusted arrival begins work")
        var performing_save := saved(sim)
        check(performing_save != null and performing_save.snapshot() == sim.snapshot(), "active work restored")
        for step in 20: sim.advance("tonsai")
        check(sim.conditions[traveler].hydration > hydration - 30 * 120, "performed drink recovered")
        if performing_save != null:
            var rebound := LocalGameSession.new(performing_save, performing_save.player_id)
            rebound.bind_physical_location("tonsai")
            check(performing_save.camps.tonsai.people[traveler].stage == "travel", "restored physical work requires arrival again")
        var after_consumption := saved(sim)
        check(after_consumption != null and after_consumption.snapshot() == sim.snapshot(), "consumption ledger restored")
        check(not sim.resource_transaction("1", own, seq, "consume", {"instance":"coconut-00", "quantity":1}), "stale replay after persistence")
        for step in 300: sim.advance("tonsai")
        check(camp.people[traveler].stage != "travel" or int(camp.people[traveler].deadline) > sim.tick - 216, "unreachable travel bounded")
        # Create an actual v2 packet at an existing technical day without rewriting history.
        var legacy := SeasonSimulation.new(sim.player_id, sim.season_id, 42)
        legacy.configure(config, cast)
        legacy.opening = packet.duplicate(true)
        legacy.ruleset_version = 2
        for old_camp: CampSimulation in legacy.camps.values(): old_camp.objects = {"fire":{"lit":false, "construction_level":0}, "shelter":{"construction_level":0}}
        legacy.tick = 5100
        legacy.revision = 5100
        var upgraded := SeasonSimulation.restore(legacy.snapshot())
        check(upgraded.ruleset_version == 3 and upgraded.day() == 3 and upgraded.calendar_seconds == 79200 + 86400 + 10800, "v2 day and fractional progress migration")
        check(upgraded.opening.opening_history == packet.opening_history, "immutable opening history retained")
        var continued := saved(upgraded)
        check(continued != null, "migrated v2 saves as v3")
        session.bind_physical_location("tonsai")
        camp.interrupt("1", sim.tick)
        var request := {"id":GameStateData.new_id(), "actor":"1", "kind":"camp.consume", "site":"shelter", "resource":"coconut", "expected_revision":sim.revision}
        check(not session.submit(request).ok, "consumption requires trusted proximity")
        session.observe_site("shelter", 1, true)
        check(session.submit(request).ok, "production command consumes resource")
        var consumed_stock: int = tribe_inventory["coconut-00"].quantity
        check(session.submit(request).ok and tribe_inventory["coconut-00"].quantity == consumed_stock, "retry cannot consume twice")
        var command_restored := saved(sim)
        if command_restored != null:
            var loaded := LocalGameSession.new(command_restored, command_restored.player_id)
            loaded.bind_physical_location("tonsai")
            loaded.observe_site("shelter", 1, true)
            check(not loaded.submit(request).ok, "stale consumption replay fails after load")
        var transfer_seq := int(sim.transaction_state.sequence) + 1
        check(sim.resource_transaction("1", own, transfer_seq, "transfer", {"instance":"rice-00", "quantity":500, "destination":own}), "permitted atomic transfer retains provenance")
        check(tribe_inventory["rice-00"].quantity == 19500, "transfer removes exact base units")
        check(not sim.resource_transaction("1", own, transfer_seq + 1, "transfer", {"instance":"rice-00", "quantity":500, "destination":rival}), "unpermitted transfer fails")
        check(saved(sim) != null, "transfer saves with original identities")
        # Small seeded matrix: same utility layer, four profiles, bounded choices.
        for style: String in ["balanced", "provider", "low_work", "exhausted"]:
            var drives := LivingCampRules.profile({"laziness":10 if style == "low_work" else 1 if style == "provider" else 5, "campcraft":10 if style == "provider" else 5})
            var condition := LivingCampRules.initial(0)
            if style == "exhausted": condition.energy = 0
            var rng := RandomNumberGenerator.new()
            rng.seed = 42
            var choices: Array[String] = ["shelter", "work", "shore", "spring"]
            var counts := {"shelter":0, "work":0, "shore":0, "spring":0}
            for sample in 50:
                counts[LivingCampRules.choose({}, condition, drives, choices, rng)] += 1
            if style == "provider": check(counts.work > counts.shore, "provider drive changes behavior")
            if style == "exhausted": check(counts.shelter == 50, "exhausted priority")
            if style == "low_work": check(counts.work < 25, "low work preference")
            var world := SeasonSimulation.restore(upgraded.snapshot())
            for id: String in world.roster:
                world._profiles[id] = drives.duplicate(true)
                world.conditions[id] = condition.duplicate(true)
            var twin := SeasonSimulation.restore(world.snapshot())
            for id: String in twin.roster: twin._profiles[id] = drives.duplicate(true)
            for step in 400:
                world.advance("")
                twin.advance("")
            check(world.snapshot() == twin.snapshot(), "seeded autonomous matrix determinism " + style)
            check(saved(world) != null, "matrix checkpoint " + style)
    print("Living Camp: %d checks, %d failures" % [checks, failures])
    quit(1 if failures else 0)
