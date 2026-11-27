extends SceneTree
var preview: MarooningPreview
var output := OS.get_environment("MAROONING_EVIDENCE_DIR")
var failures := 0
var traces: Array = []
var captures := 0
func check(ok: bool,label: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
    for i in count: await physics_frame
func touch(id: int, point: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index=id
    event.position=point
    event.pressed=pressed
    root.push_input(event,true)
func drag(id: int,point: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index=id
    event.position=point
    root.push_input(event,true)
func tap(button: Button) -> void:
    touch(742,button.get_global_rect().get_center(),true)
    await frames(2)
    touch(742,button.get_global_rect().get_center(),false)
    await frames(3)
func capture(label: String, view := "follow") -> void:
    preview._capture([view])
    await process_frame
    RenderingServer.force_draw()
    root.get_texture().get_image().save_png(output+"/%02d-%s.png"%[captures,label])
    captures+=1
    print("GUI_CAPTURE ",label)
func stick(goal: Vector3) -> void:
    var delta := goal-preview.player.position
    var yaw := preview.player.rendered_yaw()
    var direction := Vector2(delta.x*cos(yaw)-delta.z*sin(yaw),delta.x*sin(yaw)+delta.z*cos(yaw)).normalized()
    drag(41,preview.touch.home()+direction*preview.touch.radius*.75)
func walk(goal: Vector3,tolerance := .8,limit := 900) -> bool:
    var path := PackedVector3Array()
    if preview.player.position.z<8 and goal.z<8 and preview.player.position.y>.4:
        path = NavigationServer3D.map_get_path(preview.scramble.agents.values()[0].get_navigation_map(),preview.player.position,goal,true)
    touch(41,preview.touch.home(),true)
    await frames(2)
    for i in limit:
        while not path.is_empty() and MarooningDeckTraffic.planar(preview.player.position,path[0])<.2: path.remove_at(0)
        if MarooningDeckTraffic.planar(preview.player.position,goal)<tolerance:
            touch(41,preview.touch.home(),false)
            await frames(3)
            return true
        if i%6==0:
            stick(path[0] if not path.is_empty() else goal)
        if i%60==0:
            traces.append({"time":preview.scramble.simulation.elapsed+preview.race.simulation.elapsed,"position":[preview.player.position.x,preview.player.position.y,preview.player.position.z],"goal":[goal.x,goal.y,goal.z]})
        await physics_frame
    touch(41,preview.touch.home(),false)
    print("GUI_ROUTE_BLOCKED ",preview.player.position," goal ",goal)
    return false
func look_at_point(point: Vector3) -> void:
    var difference := point-preview.player.position
    var goal := atan2(-difference.x,-difference.z)
    var angle := angle_difference(preview.player.yaw,goal)
    var goal_pitch := clampf(atan2(point.y-(preview.player.position.y+1.43),Vector2(difference.x,difference.z).length()),-1.0,.42)
    var vertical := -(goal_pitch-preview.player.pitch)*minf(root.get_visible_rect().size.x,root.get_visible_rect().size.y)/(2.07*.87)
    var size := root.get_visible_rect().size
    var home := Vector2(size.x*.8,size.y*.55)
    touch(92,home,true)
    await frames(2)
    drag(92,home+Vector2(-angle*minf(size.x,size.y)/2.07,vertical))
    await frames(5)
    touch(92,home,false)
    await frames(15)
func collect_and_deposit(cycle: int,drop_first := false,attempt := 0) -> void:
    var sim := preview.scramble.simulation
    var id := int(preview.configuration.selected)
    if sim.carried(id).is_empty():
        var chosen := ""
        var distance := INF
        for item: Dictionary in sim.items.values():
            if item.state not in [MarooningScramble.State.ABOARD,MarooningScramble.State.DROPPED]: continue
            if drop_first and item.position.distance_to(sim.stations[sim.actors[id].tribe])<2.0: continue
            var current := preview.player.position.distance_to(item.position)
            if current<distance:
                chosen=item.id
                distance=current
        if chosen.is_empty(): return
        await walk(sim.items[chosen].position,1.1,600)
        await look_at_point(sim.items[chosen].position+Vector3.UP*.2)
        await frames(4)
        if preview.scramble.action_button.visible:
            await capture("target-%d"%cycle)
            await tap(preview.scramble.action_button)
            await frames(120)
    var held := sim.carried(id)
    if held.is_empty():
        if attempt<3 and sim.elapsed<80: await collect_and_deposit(cycle,drop_first,attempt+1)
        return
    await capture("pickup-%d"%cycle)
    if drop_first:
        await tap(preview.scramble.drop_button)
        await frames(100)
        await capture("drop")
        await frames(5)
        if preview.scramble.action_button.visible:
            await tap(preview.scramble.action_button)
            await frames(100)
    if sim.carried(id).is_empty(): return
    var station: Vector3 = sim.stations[sim.actors[id].tribe]
    var point := station+Vector3(-signf(station.x)*1.05,0,0)
    await walk(point,.7,600)
    await frames(130)
    await capture("deposit-%d"%cycle)
func run() -> void:
    assert(not output.is_empty(),"Set MAROONING_EVIDENCE_DIR outside the export stage")
    assert(not output.begins_with(ProjectSettings.globalize_path("res://")),"Keep evidence outside the export stage")
    DirAccess.make_dir_recursive_absolute(output)
    root.size = Vector2i(956,440)
    root.content_scale_size = Vector2i(1280,720)
    var catalog := SurvivorContestantCatalog.new()
    for count_value in [2,3]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id = 18
        var division := SurvivorSeasonConfiguration.new()
        division.count=count_value
        division.assign(catalog)
        preview=MarooningPreview.new()
        preview.catalog=catalog
        preview.configuration=division.configuration(catalog,setup)
        root.add_child(preview)
        await process_frame
        await tap(preview.skip)
        await frames(60)
        await capture("%d-baskets"%count_value,"deck")
        await tap(preview.scramble.start_button)
        var before := preview.player.position
        var yaw := preview.player.yaw
        var size := root.get_visible_rect().size
        touch(41,preview.touch.home(),true)
        touch(92,Vector2(size.x*.8,size.y*.5),true)
        await frames(2)
        drag(41,preview.touch.home()+Vector2(0,-25))
        drag(92,Vector2(size.x*.8+25,size.y*.5))
        await frames(20)
        touch(41,preview.touch.home(),false)
        touch(92,Vector2(size.x*.8+25,size.y*.5),false)
        check(before.distance_to(preview.player.position)>.01 and absf(yaw-preview.player.yaw)>.01,"Actual simultaneous native GUI move/look")
        for cycle in 3:
            await collect_and_deposit(cycle,cycle==1)
        var sim := preview.scramble.simulation
        # Deliberate nearby victim targeting; commands still enter through the primary GUI button.
        if sim.carried(18).is_empty():
            for item: Dictionary in sim.items.values():
                if item.state==MarooningScramble.State.CARRIED and item.actor!=18 and preview.player.position.distance_to(sim.actors[item.actor].position)<3:
                    var victim := int(item.actor)
                    await walk(sim.actors[victim].position,1.2,180)
                    await look_at_point(sim.actors[victim].position+Vector3.UP*.95)
                    if preview.scramble.contextual=="steal":
                        await capture("theft-target")
                        await tap(preview.scramble.action_button)
                        await frames(90)
                        await capture("theft-outcome")
                    break
        while not preview.race.started: await physics_frame
        await capture("boarding-guidance")
        await walk(Vector3(0,preview.layout.deck_y,7.5),.15,900)
        await walk(Vector3(0,preview.layout.deck_y,10.5),.25,300)
        await walk(Vector3(0,0,25),.7,800)
        var race := preview.race.simulation
        var tribe: String = race.actors[18].tribe
        var boarding := race.boarding_point(tribe)
        var outside := boarding.x+signf(boarding.x)*4.5
        await walk(Vector3(outside,0,25),1,700)
        await walk(Vector3(outside,0,boarding.z-2.5),.8,400)
        await walk(race.boarding_point(tribe),1.8,300)
        if preview.race.board.visible: await tap(preview.race.board)
        await frames(60)
        check(not race.actors[18].raft.is_empty(),"Native GUI physical boarding")
        if not race.actors[18].raft.is_empty():
            while race.phase==MarooningRace.Phase.BOARDING: await physics_frame
            for cycle in 3:
                while fmod(race.elapsed,MarooningRace.BEAT)/MarooningRace.BEAT<.49: await physics_frame
                await tap(preview.race.paddle)
                await frames(70)
            await capture("paddle-ui")
            await tap(preview.race.jump)
            await capture("jump-swimmer")
            for step in 12:
                if preview.race.board.visible:
                    await tap(preview.race.board)
                    await frames(50)
                    break
                await walk(race.boarding_point(tribe),2.1,90)
        var reward_captured := false
        for frame in 18000:
            await physics_frame
            if not race.reward.tribe.is_empty() and not reward_captured:
                await capture("reward","race")
                reward_captured=true
            if race.rafts[tribe].arrived and race.actors[18].raft.is_empty() and race.actors[18].mode!="arrived":
                var raft: Dictionary = race.rafts[tribe]
                var local := (preview.player.position-(raft.position as Vector3)).rotated(Vector3.UP,-float(raft.heading))
                if local.z<7:
                    var goal := (raft.position as Vector3)+Vector3(5,0,7).rotated(Vector3.UP,float(raft.heading))
                    await walk(goal,1,800)
                await walk(race.arrival_point(18),2.0,1200)
            elif race.actors[18].raft.is_empty() and race.phase!=MarooningRace.Phase.ARRIVAL_COMPLETE and not race.rafts[tribe].arrived:
                # Independent swimmer route remains physical if a moving raft gets away.
                await walk(Vector3(8,0,165),1,6000)
            if race.phase==MarooningRace.Phase.ARRIVAL_COMPLETE: break
        await capture("summary","landing")
        check(race.phase==MarooningRace.Phase.ARRIVAL_COMPLETE,"Native GUI continuous arrival")
        print("GUI_RESULT ",count_value," contributions ",sim.contributions[18]," boardings ",race.actors[18].boardings," strokes ",race.actors[18].strokes," phase ",race.phase)
        var file := FileAccess.open(output+"/trace-%d.json"%count_value,FileAccess.WRITE)
        file.store_string(JSON.stringify({"trace":traces,"scramble":sim.result(preview.routes),"race":race.result()}))
        file.close()
        await tap(preview.scramble.restart_button)
        await frames(10)
        check(preview.introducing,"Native GUI restart")
        preview.queue_free()
        await process_frame
    print("Native GUI: ",failures," failures")
    quit(1 if failures else 0)
