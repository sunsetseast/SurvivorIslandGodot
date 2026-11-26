extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available:
        # Same technical fixture factory as the existing marooning regression.
        var fixture_script := load("res://tests/marooning_test.gd")
        catalog = fixture_script.fixture()
    for count_value in [2,3]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id = 18
        var division := SurvivorSeasonConfiguration.new()
        division.count = count_value
        division.assign(catalog)
        var preview := MarooningPreview.new()
        preview.catalog = catalog
        preview.configuration = division.configuration(catalog,setup)
        var original := preview.configuration.duplicate(true)
        var old_steps := Engine.max_physics_steps_per_frame
        root.add_child(preview)
        await process_frame
        preview.finish_intro()
        for frame in 60:
            await physics_frame
        preview.scramble.start()
        # Exercise actual scramble expiry and continuous transition, starting from
        # authentic deck positions. No boarding relocation or command bypass.
        preview.scramble.simulation.duration = 120.0
        var pilot_ready := false
        var paused_tested := false
        for frame in 24000:
            await physics_frame
            var sim := preview.race.simulation
            if preview.race.started and not pilot_ready:
                preview.player.set_physics_process(false)
                var agent := NavigationAgent3D.new()
                preview.player.add_child(agent)
                preview.scramble.agents[18] = agent
                pilot_ready = true
            if pilot_ready and sim.actors[18].raft.is_empty() and sim.actors[18].mode != "arrived":
                # Technical pilot drives the same physical motor, never relocates.
                preview.race.move_npc(18,1.0/60)
            if pilot_ready and sim.elapsed > 45 and not paused_tested:
                preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
                var frozen := sim.elapsed
                for pause_frame in 10:
                    await physics_frame
                check(sim.elapsed == frozen,"Focus loss freezes race and rhythm")
                preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
                paused_tested = true
            if frame % 1800 == 0:
                var states := {}
                for id: int in sim.actors:
                    states[id] = {"mode":sim.actors[id].mode,"position":preview.cast[id].position,"raft":sim.actors[id].raft}
                for id: int in sim.actors:
                    var actor_state: Dictionary = sim.actors[id]
                    if not actor_state.raft.is_empty():
                        var local_position: Vector3 = preview.race.vessels[actor_state.tribe].to_local(preview.cast[id].position)
                        check(local_position.distance_to(MarooningRace.seat(int(actor_state.seat_index)))<.001,"Physical crew follows the actual platform without drift")
                print("PHYSICAL ",count_value," frame ",frame," phase ",sim.phase," states ",states)
            if sim.phase == MarooningRace.Phase.ARRIVAL_COMPLETE:
                break
        var race := preview.race.simulation
        var boarded := 0
        var recoveries := 0
        for actor: Dictionary in race.actors.values():
            boarded += int(actor.boardings)
        for event: Dictionary in race.events:
            recoveries += int(event.action == "navigation_recovery")
        print("PHYSICAL_RESULT tribes=",count_value," boarded=",boarded," recoveries=",recoveries," reward=",race.reward," elapsed=",race.elapsed)
        var participating := 0
        for actor: Dictionary in race.actors.values():
            participating += int(int(actor.boardings)>0 or float(actor.swim_distance)>1)
        check(participating == 18,"All contestants board or independently swim")
        check(boarded >= 12,"Physical boarding remains the predominant route")
        check(race.phase == MarooningRace.Phase.ARRIVAL_COMPLETE,"Full continuous physical arrival completes")
        check(preview.has_meta("marooning_result"),"Transient handoff available")
        check(not race.reward.tribe.is_empty(),"Physical NPC competition claims reward")
        check(preview.configuration==original and preview.cast.size()==18,"Preserve configuration and all identities")
        for tribe: String in race.rafts:
            var raft: Dictionary = race.rafts[tribe]
            print("PHYSICAL_RAFT ",tribe," cargo_kg=",raft.cargo_kg," peak_mass_kg=",raft.peak_mass_kg," speed_max=",raft.max_speed," arrival=",raft.arrival_time)
        preview.restart_scramble()
        await process_frame
        check(preview.cast.size()==18 and preview.race.vessels.size()==count_value and not preview.has_meta("marooning_result"),"Restart replaces actors/platforms and clears handoff")
        preview.queue_free()
        await process_frame
        check(Engine.max_physics_steps_per_frame==old_steps,"Physics policy restored")
    print("Race physical: ",failures," failures")
    quit(1 if failures else 0)
