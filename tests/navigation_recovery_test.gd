extends SceneTree
## Exceptional recovery fixture: the physical motor is deliberately held immobile.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",label)
func run() -> void:
    root.size=Vector2i(956,440)
    var catalog: SurvivorContestantCatalog=load("res://tests/marooning_test.gd").fixture()
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id=18
    var division := SurvivorSeasonConfiguration.new()
    division.assign(catalog)
    var preview := MarooningPreview.new()
    preview.catalog=catalog
    preview.configuration=division.configuration(catalog,setup)
    root.add_child(preview)
    await process_frame
    preview.finish_intro()
    preview.set_physics_process(false)
    preview.session.start(false)
    var id := int(preview.scramble.agents.keys()[0])
    var body: CampPhysicalMotor=preview.cast[id]
    var state: Dictionary=preview.session.race.actors[id]
    var from := Vector3(20,-1.07,40)
    var goal := Vector3(20,-1.07,100)
    body.position=from
    state.position=from
    state.place="swimming"
    state.mode="swimming"
    var human_before := preview.player.position
    for frame in 3: await physics_frame
    for step in 2800:
        preview.session.advance(MarooningSession.STEP)
        preview.race.watch_progress(id,goal,MarooningSession.STEP)
        if step%60==0: await physics_frame
    for frame in 40: await physics_frame
    check(preview.session.recoveries.size()==1,"Only one exceptional recovery after measured45s and8+ physical retries")
    check(body.position.distance_to(from)>2 and body.position.distance_to(from)<3,"Recovery is a local collision-checked safe-zone move")
    check((body.position-from).dot((goal-from).normalized())<=.05,"Recovery does not award forward route progress")
    check(state.recovered and not state.arrived,"Recovery is explicit and does not fabricate arrival")
    check(preview.session.race.reward.status=="available","Recovery cannot award the exclusive reward")
    var secured := 0
    for item: Dictionary in preview.session.scramble.items.values(): secured+=int(item.state==MarooningScramble.State.SECURED)
    check(secured==0 and preview.session.scramble.items.size()==50,"No fabricated cargo or lost identities")
    check(not preview.race.safe_assist(18,goal,100,"human_fixture"),"Human can never be silently moved")
    check(preview.player.position.distance_to(human_before)<.2,"Human remains under own controller")
    # Separate catastrophic-physics fixture: near-zero horizontal distance must
    # not hide a contestant below the surface. Restart behind the dry region.
    var shore: Vector3=preview.session.race.rafts[state.tribe].shore_center
    body.position=Vector3(shore.x,-5,shore.z-1.8)
    state.position=body.position
    state.place="swimming"
    state.arrived=false
    state.recovered=false
    preview.race.progress.erase(id)
    var dry_goal := Vector3(shore.x,shore.y,shore.z-1.8)
    for step in 2800:
        preview.session.advance(MarooningSession.STEP)
        preview.race.watch_progress(id,dry_goal,MarooningSession.STEP)
        if step%60==0: await physics_frame
    for frame in 40: await physics_frame
    check(preview.session.recoveries.size()==2,"Below-surface progress also has a bounded explicit fallback")
    check(state.recovered and not state.arrived,"Repair cannot manufacture confirmed arrival")
    check(MarooningRace.planar(body.position,preview.session.race.rafts[state.tribe].shore_center)>8,"Repaired NPC must physically return from outside arrival region")
    check(body.position.y>=preview.layout.bed(body.position.x,body.position.z),"Repair destination is above real surface")
    check(preview.session.race.reward.status=="available","Surface repair cannot award reward")
    print("RECOVERY_FIXTURE ",preview.session.recoveries)
    preview.queue_free()
    await process_frame
    print("Navigation recovery: ",failures," failures")
    quit(1 if failures else 0)
