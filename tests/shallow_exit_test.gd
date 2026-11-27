extends SceneTree
## Regression of a voluntary exit immediately before physical grounding.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL: ",label)
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available: catalog=load("res://tests/marooning_test.gd").fixture()
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id=18
    var division := SurvivorSeasonConfiguration.new()
    division.count=3
    division.seed_value=4233012246
    division.assign(catalog)
    var preview := MarooningPreview.new()
    preview.catalog=catalog
    preview.configuration=division.configuration(catalog,setup)
    root.add_child(preview)
    await process_frame
    preview.finish_intro()
    var race := preview.session.race
    var tribe: String=race.actors[18].tribe
    var raft: Dictionary=race.rafts[tribe]
    raft.position=Vector3(-.826656,.55,151.4)
    raft.heading=.304043853952598
    raft.waypoints.clear()
    var id := 0
    for actor_id: int in race.actors:
        var actor: Dictionary=race.actors[actor_id]
        actor.collect_until=INF
        if actor.tribe!=tribe: continue
        actor.raft=tribe
        actor.place="aboard"
        actor.mode="aboard"
        raft.crew.append(actor_id)
        actor.position=race.to_world(tribe,MarooningRace.seat(int(actor.seat_index)))
        if int(actor.seat_index)==2: id=actor_id
    race.reward.status="unclaimed"
    race.reward.location="unclaimed"
    for frame in 30: await physics_frame
    preview.session.start(false)
    check(race.commit_launch(tribe,"shallow_exit_fixture"),"Actual crew powers the fixture")
    check(race.leave(id),"Voluntary underway exit")
    var point: Vector3=race.actors[id].position
    check(point.y>=preview.layout.bed(point.x,point.z)+.035,"Underway endpoint is above actual shallow seabed")
    var minimum_clearance := INF
    for frame in 3600:
        await physics_frame
        var body: CampPhysicalMotor=preview.cast[id]
        minimum_clearance=minf(minimum_clearance,body.position.y-preview.layout.bed(body.position.x,body.position.z))
        if race.actors[id].arrived: break
    print("SHALLOW_EXIT ",JSON.stringify({"actor":id,"elapsed":race.elapsed,"position":race.actors[id].position,"minimum_clearance":minimum_clearance,"arrived":race.actors[id].arrived}))
    check(race.actors[id].arrived,"NPC physically wades/walks into broad dry arrival")
    check(minimum_clearance>=-.08,"No below-seabed trajectory")
    check(preview.session.recoveries.is_empty(),"Normal shallow exit needs zero exceptional assists")
    check(preview.session.scramble.items.size()==50,"All instances retained")
    preview.queue_free()
    await process_frame
    print("Shallow exit: ",failures," failures")
    quit(1 if failures else 0)
