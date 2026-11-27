extends SceneTree
var failures := 0
func check(value: bool,label: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available: catalog = load("res://tests/marooning_test.gd").fixture()
    for scenario: Array in [[2,"Balanced",1,18],[3,"Balanced",42,1],[3,"Brains / Brawn / Beauty",99,7],[2,"Battle of the Sexes",7,3],[2,"Random",99,10],[3,"Random",1,14],[2,"Manual",42,4],[3,"Manual",7,16]]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id = int(scenario[3])
        var division := SurvivorSeasonConfiguration.new()
        division.count = int(scenario[0])
        division.method = scenario[1]
        division.seed_value = int(scenario[2])
        division.assign(catalog)
        var preview := MarooningPreview.new()
        preview.catalog = catalog
        preview.configuration = division.configuration(catalog,setup)
        root.add_child(preview)
        await process_frame
        preview.finish_intro()
        for frame in 60: await physics_frame
        var sim := preview.scramble.simulation
        # A separate stress fixture: 6/9 physical carriers initially approach one station.
        # No action award or subsequent relocation; all 18 scene bodies remain present.
        var crew: Array = []
        for tribe: Dictionary in preview.configuration.tribes:
            if int(setup.selected_id) not in tribe.members:
                crew = tribe.members
                break
        var cargo: Array[String] = []
        for id: int in crew:
            if id == int(setup.selected_id): continue
            var item_id: String = sim.items.keys()[cargo.size()]
            sim.items[item_id].state = MarooningScramble.State.CARRIED
            sim.items[item_id].actor = id
            cargo.append(item_id)
        preview.scramble.start()
        var previous := {}
        var jam := {}
        var longest := 0.0
        for frame in 5400:
            await physics_frame
            if frame%60==0:
                for id: int in preview.scramble.agents:
                    var point: Vector3 = preview.cast[id].position
                    var moving := not sim.carried(id).is_empty() and not sim.pending.has(id) and preview.scramble.traffic.slots.has(id)
                    var stalled := previous.has(id) and MarooningDeckTraffic.planar(previous[id],point)<.1
                    jam[id] = float(jam.get(id,0))+1.0 if moving and stalled else 0.0
                    longest = maxf(longest,float(jam[id]))
                    previous[id] = point
        var delivered := 0
        for item_id: String in cargo: delivered += int(sim.items[item_id].state==MarooningScramble.State.SECURED)
        check(delivered==cargo.size(),"All simultaneous carriers physically deposit: "+str(scenario))
        check(longest<=8,"No persistent carrier jam over 8s: "+str(scenario)+" longest="+str(longest))
        check(sim.items.size()==50 and preview.cast.size()==18,"Conserve instances and contestant participation")
        print("DECK_STRESS ",JSON.stringify({"scenario":scenario,"carriers":cargo.size(),"delivered":delivered,"longest_carrier_jam":longest,"path_resets":preview.scramble.traffic.resets}))
        preview.queue_free()
        await process_frame
    print("Deck traffic: ",failures," failures")
    quit(1 if failures else 0)
