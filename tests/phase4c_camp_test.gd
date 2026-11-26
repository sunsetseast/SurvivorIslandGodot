extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", label)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    for count_value in [2, 3]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id = 11
        var division := SurvivorSeasonConfiguration.new()
        division.count = count_value
        division.assign(catalog)
        var sim := SeasonSimulation.new("a".repeat(32), "b".repeat(32), 1)
        sim.configure(division.configuration(catalog, setup), catalog)
        var camp := load("res://tonsai/camp.tscn").instantiate() as TonsaiCamp
        camp.session = LocalGameSession.new(sim, sim.player_id)
        root.add_child(camp)
        check(camp.loaded and camp.inhabitants.size() == 18 / count_value - 1, "Correct playable rigs")
        for npc: TonsaiNpc in camp.inhabitants:
            check(npc.position.distance_to(camp.player.position) > .9, "Player clearance")
            for other: TonsaiNpc in camp.inhabitants:
                if npc != other:
                    check(npc.position.distance_to(other.position) > .9, "NPC clearance")
        for tick in 18:
            await physics_frame
        camp.player.position = camp.inhabitants[0].position + Vector3(0, 0, 1.2)
        await physics_frame
        check(camp.begin_talk(), "Conversation available")
        check(not camp.respond(&"water").is_empty(), "Conversation reply")
        camp.end_talk()
        check(camp.checkpoint_player(), "Pose checkpoint")
        var state := camp.local_host.checkpoint()
        check(state.world.tonsai.people["11"].journal.size() == 1, "Selected participant journal")
        check(SaveCodec.decode(SaveCodec.encode(state, 1, 100)).status == "valid", "Pose and journal save")
        camp.queue_free()
        await process_frame
    print("PHASE 4C camp failures: ", failures)
    quit(1 if failures else 0)
