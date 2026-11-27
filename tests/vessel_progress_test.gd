extends SceneTree
## Technical collision regression at observed dock contact, not journey evidence.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL: ",label)
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available: catalog=load("res://tests/marooning_test.gd").fixture()
    for start: Vector3 in [Vector3(-4.866607,.55,110.7564),Vector3(4.866607,.55,110.7564),Vector3(0,.55,108.2)]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id=18
        var division := SurvivorSeasonConfiguration.new()
        division.seed_value=1372773787
        division.assign(catalog)
        var preview := MarooningPreview.new()
        preview.catalog=catalog
        preview.configuration=division.configuration(catalog,setup)
        root.add_child(preview)
        await process_frame
        preview.finish_intro()
        preview.session.start(false)
        var race := preview.session.race
        var tribe: String=race.actors[18].tribe
        var raft: Dictionary=race.rafts[tribe]
        # Explicit initial fixture: full crew already aboard the real loaded hull.
        raft.position=start
        raft.dock_side=-1.0 if start.x<race.reward_position.x else 1.0
        raft.heading=-signf(start.x)*.107152441
        raft.waypoints.clear()
        for id: int in race.actors:
            var actor: Dictionary=race.actors[id]
            actor.collect_until=INF
            if actor.tribe!=tribe: continue
            actor.raft=tribe
            actor.place="aboard"
            actor.mode="aboard"
            raft.crew.append(id)
            actor.position=race.to_world(tribe,MarooningRace.seat(int(actor.seat_index)))
        for item_id: String in preview.session.scramble.items.keys().slice(0,24):
            var item: Dictionary=preview.session.scramble.items[item_id]
            item.state=MarooningScramble.State.SECURED
            item.tribe=tribe
            item.actor=0
            item["secured_at"]=-10.0
            item["location"]="raft"
        check(race.commit_launch(tribe,"technical_dock_fixture"),"Fixture has actual willing crew")
        race.reward.status="unclaimed"
        race.reward.location="unclaimed"
        for frame in 7200:
            await physics_frame
            race.stroke(18)
            if raft.arrived: break
        print("DOCK_PROGRESS ",JSON.stringify({"start":start,"end":raft.position,"elapsed":race.elapsed,"distance":raft.distance,"repaths":raft.repaths,"arrived":raft.arrived}))
        check(raft.arrived,"Real hull clears dock and physically reaches shore")
        check(preview.session.recoveries.is_empty(),"No relocation/fade assist")
        check(preview.session.scramble.items.size()==50,"Exact ledger retained")
        preview.queue_free()
        await process_frame
    print("Vessel progress: ",failures," failures")
    quit(1 if failures else 0)
