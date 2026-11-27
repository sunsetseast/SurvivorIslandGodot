extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",label)
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available: catalog=load("res://tests/marooning_test.gd").fixture()
    for count_value in [2,3]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id=18
        var division := SurvivorSeasonConfiguration.new()
        division.count=count_value
        division.assign(catalog)
        var preview := MarooningPreview.new()
        preview.catalog=catalog
        preview.configuration=division.configuration(catalog,setup)
        root.add_child(preview)
        await process_frame
        preview.finish_intro()
        preview.player.set_physics_process(false)
        var agent := NavigationAgent3D.new()
        preview.player.add_child(agent)
        preview.scramble.agents[18]=agent
        preview.scramble.traffic.configure_agent(18)
        for frame in 60: await physics_frame
        preview.session.start(false)
        var captured := false
        for frame in 21600:
            await physics_frame
            var state: Dictionary=preview.session.race.actors[18]
            if not preview.race.transitions.has(18) and state.raft.is_empty() and not preview.session.race.pending.has(18): preview.race.move_npc(18,1.0/60)
            if not state.raft.is_empty(): preview.session.race.stroke(18)
            if not captured and not OS.get_environment("MAROONING_CAPTURE_DIR").is_empty() and not state.raft.is_empty() and preview.session.race.rafts[state.tribe].crew.size()>=count_value*0+5:
                preview._capture(["raft-side"])
                await process_frame
                RenderingServer.force_draw(true)
                root.get_texture().get_image().save_png(OS.get_environment("MAROONING_CAPTURE_DIR")+"/wip-seated-%d.png"%count_value)
                preview._capture(["follow"])
                captured=true
            if frame%1800==0:
                for body_id in [12,18]:
                    var body: CampPhysicalMotor=preview.cast[body_id]
                    var contacts := []
                    for ci in body.get_slide_collision_count():
                        var obj := body.get_slide_collision(ci).get_collider()
                        contacts.append(str(obj.get_parent().name) if obj!=null else "none")
                    print("STUCK_AUDIT ",body_id," ",{"goal":preview.scramble.traffic.goals.get(body_id),"intent":preview.scramble.traffic.intents.get(body_id),"safe":preview.scramble.traffic.safe.get(body_id),"blocked":preview.scramble.traffic.blocked.get(body_id),"pending":preview.session.scramble.pending.get(body_id),"wants":preview.session.wants_departure(body_id),"locked":preview.player.locked,"contact":contacts})
                var actors := {}
                for id: int in preview.cast:
                    actors[id]={"place":preview.session.race.actors[id].place,"p":preview.cast[id].position,"raft":preview.session.race.actors[id].raft}
                print("CONCURRENT_PHYSICAL ",count_value," t=",preview.session.elapsed," actors=",actors)
                for tribe: String in preview.session.race.rafts:
                    var raft: Dictionary=preview.session.race.rafts[tribe]
                    print("VESSEL ",tribe," ",raft.state," ",raft.position," crew=",raft.crew," waypoints=",raft.waypoints," blocked=",raft.blocked_seconds)
            if preview.session.state==MarooningSession.State.COMPLETE: break
        print("CONCURRENT_RESULT ",count_value," time=",preview.session.elapsed," reward=",preview.session.race.reward)
        if not OS.get_environment("MAROONING_CAPTURE_DIR").is_empty():
            var file := FileAccess.open(OS.get_environment("MAROONING_CAPTURE_DIR")+"/physical-journal-%d.json"%count_value,FileAccess.WRITE)
            file.store_string(JSON.stringify(preview.session.result()))
        check(preview.session.state==MarooningSession.State.COMPLETE,"Physical concurrent full arrival "+str(count_value))
        check(preview.session.scramble.items.size()==50,"All50 preserved")
        preview.queue_free()
        await process_frame
    print("Concurrent physical: ",failures," failures")
    quit(1 if failures else 0)
