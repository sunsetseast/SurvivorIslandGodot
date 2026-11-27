extends SceneTree
## Full ordinary UI pilot. Only touch events drive the selected contestant.
var app: SurvivorGameApp
var preview: MarooningPreview
var failures := 0
var captures := {}
var move_down := false
var record_dir := ""
var permanent_mode := false
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",label)
func frames(count_value: int) -> void:
    for frame in count_value: await physics_frame
func touch(id: int,point: Vector2,pressed: bool) -> void:
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
func tap(control: Button) -> bool:
    if not is_instance_valid(control) or not control.is_visible_in_tree() or control.disabled: return false
    var point := control.get_global_rect().get_center()
    touch(742,point,true)
    await frames(2)
    touch(742,point,false)
    await frames(3)
    return true
func action(command: String) -> bool:
    if not is_instance_valid(preview): return false
    preview.hud.update_state()
    for pair: Array in [[preview.hud.command,preview.hud.primary],[preview.hud.second_command,preview.hud.secondary],[preview.hud.third_command,preview.hud.tertiary]]:
        if pair[0]==command: return await tap(pair[1])
    return false
func capture(label: String,view := "follow") -> void:
    if permanent_mode or record_dir.is_empty() or DisplayServer.get_name()=="headless" or not is_instance_valid(preview): return
    preview._capture([view])
    await process_frame
    RenderingServer.force_draw(true)
    root.get_texture().get_image().save_png(record_dir+"/"+label+".png")
    print("TOUCH_CAPTURE ",label)
    preview._capture(["follow"])
func walk(point: Vector3,tolerance := .6,maximum := 25.0,board_near := false) -> bool:
    var home := preview.touch.home()
    touch(41,home,true)
    move_down=true
    var end := preview.session.elapsed+maximum
    var reached := false
    for frame in int(maximum*60)+180:
        if not is_instance_valid(preview): return true
        var actor: Dictionary=preview.session.race.actors[int(preview.configuration.selected)]
        if board_near and preview.session.race.can_board(int(preview.configuration.selected)):
            touch(41,home,false)
            move_down=false
            return await action("board")
        if not actor.raft.is_empty() or preview.session.state==MarooningSession.State.COMPLETE:
            reached=true
            break
        var difference := point-preview.player.position
        difference.y=0
        if difference.length()<tolerance:
            reached=true
            break
        var yaw := preview.player._stick_yaw if preview.player._stick_active else preview.player.rendered_yaw()
        var local := difference.normalized().rotated(Vector3.UP,-yaw)
        var power := clampf(difference.length()/2.0,.28,1)
        drag(41,home+Vector2(local.x,local.z)*preview.touch.radius*(.13+.87*power))
        await physics_frame
        if not is_instance_valid(preview): return true
        if preview.session.elapsed>=end: break
    touch(41,home,false)
    move_down=false
    await frames(2)
    if not is_instance_valid(preview): return true
    print("TOUCH_WALK goal=",point," position=",preview.player.position," clock=",preview.session.elapsed," reached=",reached)
    return reached
func choose(count_value: int) -> bool:
    if not app._actions.has("new"):
        for attempt in 5:
            if app._actions.has("new"): break
            if app._actions.has("back"): await tap(app._actions.back)
            await frames(5)
    check(await tap(app._actions.new),"New Game touch")
    await frames(10)
    for attempt in 12:
        var row: Button=app._actions.get("cast_18")
        var rect := app._selection._roster_scroll.get_global_rect()
        if row!=null and rect.has_point(row.get_global_rect().get_center()):
            check(await tap(row),"Select approved contestant through roster")
            break
        var start := rect.position+rect.size*Vector2(.5,.8)
        touch(91,start,true)
        for step in 10:
            drag(91,start-Vector2(0,float(step+1)*rect.size.y*.055))
            await frames(2)
        touch(91,start-Vector2(0,rect.size.y*.55),false)
        await frames(8)
    check(app.selection_setup.selected_id==18,"Chosen identity18")
    check(await tap(app._actions.select),"Confirm Survivor touch")
    await frames(5)
    check(await tap(app._actions.standard),"Standard season touch")
    check(await tap(app._actions["Two Tribes" if count_value==2 else "Three Tribes"]),"Format touch")
    await frames(8)
    if permanent_mode:
        for attempt in 14:
            var rect := app._account_scroll.get_global_rect()
            if rect.has_point(app._actions.confirm.get_global_rect().get_center()): break
            var start := rect.position+rect.size*Vector2(.5,.8)
            touch(91,start,true)
            for step in 10:
                drag(91,start-Vector2(0,float(step+1)*rect.size.y*.055))
                await frames(2)
            touch(91,start-Vector2(0,rect.size.y*.55),false)
            await frames(8)
        check(await tap(app._actions.confirm),"Confirm permanent season touch")
        await frames(5)
        if not app._actions.has("slot1"):
            check(false,"Tribe confirmation must reach empty slots")
            return false
        check(await tap(app._actions.slot1),"Empty slot touch starts marooning")
        check(app.saves.inspect(1).status=="empty","No permanent save before arrival")
    else:
        check(await tap(app._actions.marooning),"Private marooning touch")
    await frames(10)
    if not is_instance_valid(app._marooning): return false
    preview=app._marooning
    if permanent_mode and not OS.get_environment("OPENING_RESULT_PATH").is_empty():
        preview.completed.connect(func(result: Dictionary) -> void:
            var file := FileAccess.open(OS.get_environment("OPENING_RESULT_PATH"),FileAccess.WRITE)
            file.store_var(result))
    check(preview.session.elapsed==0,"Intro does not consume gameplay time")
    check(await action("skip"),"Skip introduction touch")
    check(await action("start"),"Start touch")
    await frames(190)
    return preview.session.state==MarooningSession.State.ACTIVE
func run() -> void:
    record_dir=OS.get_environment("MAROONING_CAPTURE_DIR")
    permanent_mode=OS.get_environment("PERMANENT_OPENING_TOUCH")=="1"
    if permanent_mode and OS.get_environment("OPENING_RENDER_CAPTURES")=="1":
        RenderingServer.render_loop_enabled=false
    root.size=Vector2i(956,440)
    root.content_scale_size=Vector2i(1280,720)
    app=load("res://application/game_app.tscn").instantiate()
    root.add_child(app)
    if permanent_mode:
        var isolated := LocalDataStore.new("permanent-touch-"+GameStateData.new_id())
        app.profile=PlayerProfile.new(isolated)
        app.saves=LocalSaveProvider.new(isolated)
        app._main()
    await frames(30)
    if not OS.get_environment("OPENING_REPLAY_RESULT_PATH").is_empty():
        var file := FileAccess.open(OS.get_environment("OPENING_REPLAY_RESULT_PATH"),FileAccess.READ)
        var recorded: Dictionary=file.get_var()
        app._configured=true
        app.selection_setup.selected_id=int(recorded.configuration.selected)
        app.selection_setup.information_mode=recorded.configuration.information
        app.division.count=recorded.configuration.tribes.size()
        app.division.seed_value=int(recorded.configuration.seed)
        app.division.method=recorded.configuration.method
        app.division.tribes=recorded.configuration.tribes.duplicate(true)
        app._new(1)
        preview=app._marooning
        preview.completed.emit(recorded)
        await finish_permanent(recorded.configuration.tribes.size())
        app.queue_free()
        await frames(4)
        if DisplayServer.get_name()!="headless": RenderingServer.force_draw(true)
        print("Retained real handoff input acceptance: ",failures," failures")
        quit(1 if failures else 0)
        return
    var formats := [2,3]
    if not OS.get_environment("MAROONING_TOUCH_FORMAT").is_empty(): formats=[int(OS.get_environment("MAROONING_TOUCH_FORMAT"))]
    for count_value in formats:
        check(await choose(count_value),"Ordinary UI reached active marooning "+str(count_value))
        if not is_instance_valid(preview): break
        var selected := int(preview.configuration.selected)
        var state: Dictionary=preview.session.race.actors[selected]
        var gate: Vector3=preview.routes[state.tribe].deck_access
        # A simultaneous two-finger move/look burst, sent through the viewport.
        var before := preview.player.position
        var yaw_before := preview.player.yaw
        var home := preview.touch.home()
        var look := Vector2(root.get_visible_rect().size.x*.58,root.get_visible_rect().size.y*.35)
        touch(41,home,true)
        touch(92,look,true)
        for frame in 20:
            drag(41,home+Vector2(0,-preview.touch.radius*.75))
            drag(92,look+Vector2(frame*1.7,0))
            await physics_frame
        touch(41,home,false)
        touch(92,look,false)
        check(preview.player.position.distance_to(before)>.05 and absf(preview.player.yaw-yaw_before)>.01,"Genuine simultaneous move/look")
        await capture("native-%d-deck"%count_value)
        if count_value==3:
            # Remain eligible on deck for the full60-second route.
            for frame in 3600:
                if preview.session.elapsed>=60: break
                if preview.hud.command=="pickup": await action("pickup")
                if not preview.session.scramble.carried(selected).is_empty():
                    var station: Vector3=preview.session.scramble.stations[state.tribe]
                    await walk(station+Vector3(-signf(station.x)*1.05,0,0),.7,12)
                    await frames(100)
                await frames(10)
            check(preview.session.elapsed>=60,"Full minute collecting route")
        await walk(Vector3(signf(gate.x)*1.35,preview.layout.deck_y,preview.player.position.z),.5,15)
        await walk(Vector3(signf(gate.x)*1.35,preview.layout.deck_y,gate.z),.5,15)
        await walk(gate,.15,15)
        var jumped := false
        for attempt in 3:
            await action("jump_deck")
            jumped=preview.race.transitions.has(selected)
            if jumped: break
            print("JUMP_TOUCH_BLOCKED ",{"position":preview.player.position,"reason":preview.race.feedback,"attempt":attempt})
            # A tapped button is not an accepted jump. Follow the ordinary
            # access feedback, clear the approach physically and retry input.
            await walk(gate+Vector3(signf(gate.x)*.15,0,attempt*.3),.12,4)
            await frames(30)
        check(jumped and preview.race.transitions.has(selected),"Real open-side jump touch "+str(count_value))
        await frames(100)
        check(state.place=="swimming" and preview.player.swimming(),"Side jump physically reaches clear water")
        await capture("native-%d-water"%count_value)
        if count_value==2:
            await walk(Vector3(signf(gate.x)*9.8,-1.07,preview.player.position.z),.5,15,true)
            var board_end := preview.session.elapsed+25
            while state.raft.is_empty() and preview.session.elapsed<board_end:
                if preview.session.race.can_board(selected): await action("board")
                else: await walk(preview.session.race.boarding_access(selected),.3,3,true)
                await frames(10)
            await frames(240)
            check(not state.raft.is_empty(),"Human boards moored raft through touch")
            await action("launch")
        var tested_reboard := false
        var cleared_grounded_hull := false
        var paddles := 0
        var deadline := preview.session.elapsed+300
        while is_instance_valid(preview) and preview.session.state!=MarooningSession.State.COMPLETE and preview.session.elapsed<deadline:
            var raft: Dictionary=preview.session.race.rafts[state.tribe]
            if not state.raft.is_empty():
                if preview.hud.command=="claim_reward": await action("claim_reward")
                if raft.state=="moored": await action("launch")
                elif raft.state=="underway":
                    if paddles<3 or absf(fmod(preview.session.elapsed,MarooningRace.BEAT)/MarooningRace.BEAT-.5)<.04:
                        if await action("paddle"): paddles+=1
                    if count_value==2 and paddles>=3 and not tested_reboard:
                        await capture("native-paddling")
                        check(await action("jump_off"),"Deliberate moving jump touch")
                        var boardings_before := int(state.boardings)
                        for frame in 70: await physics_frame
                        check(state.raft.is_empty(),"Moving jump actually released membership")
                        print("REBOARD_TOUCH_STATE ",{"position":preview.player.position,"access":preview.session.race.boarding_access(selected),"range":preview.player.position.distance_to(preview.session.race.boarding_access(selected)),"pending":preview.session.race.pending.has(selected),"transition":preview.race.transitions.has(selected),"can_board":preview.session.race.can_board(selected)})
                        var reboard := await action("board")
                        if not reboard: reboard=await walk(preview.session.race.boarding_access(selected),.3,3,true)
                        check(reboard,"Moving side/stern reboard touch")
                        await frames(240)
                        check(not state.raft.is_empty() and int(state.boardings)==boardings_before+1,"Moving reboard physically completed exactly once")
                        tested_reboard=true
                        await capture("native-moving-reboard")
            elif not preview.race.transitions.has(selected) and not preview.session.race.pending.has(selected):
                if not cleared_grounded_hull and raft.state=="grounded" and preview.player.position.z>raft.position.z-14 and preview.player.position.z<raft.position.z+10:
                    # Steer around the visible grounded hull, rather than drive
                    # diagonally through its side on the way to dry shore.
                    var side := -1.0 if preview.player.position.x<raft.position.x else 1.0
                    var outside := Vector3(raft.position.x+side*7,preview.player.position.y,preview.player.position.z)
                    await walk(outside,.65,8)
                    await walk(Vector3(outside.x,outside.y,raft.position.z+12),1.0,14)
                    cleared_grounded_hull=true
                var goal := preview.session.race.actor_objective(selected)
                await walk(goal,1.5,3)
                if is_instance_valid(preview) and preview.hud.command=="claim_reward": await action("claim_reward")
            await frames(3)
        if permanent_mode:
            await finish_permanent(count_value)
            break
        check(preview.session.state==MarooningSession.State.COMPLETE,"Full touch journey reaches summary "+str(count_value))
        check(preview.has_meta("marooning_result"),"Version2 transient result")
        check(preview.session.recoveries.is_empty(),"Representative touch journey needs no exceptional recovery")
        if not record_dir.is_empty():
            var result_file := FileAccess.open(record_dir+"/native-%d-handoff.json"%count_value,FileAccess.WRITE)
            result_file.store_string(JSON.stringify(preview.session.result(),"  "))
        check(not preview.player.locked,"Player retains shore look/walk")
        print("NATIVE_TOUCH_RESULT tribes=",count_value," time=",preview.session.elapsed," strokes=",state.strokes," arrived=",state.arrived," result=",preview.session.state)
        await capture("native-%d-summary"%count_value)
        check(await tap(preview.hud.actions.restart),"Restart touch")
        await frames(10)
        check(preview.session.elapsed==0 and preview.introducing and preview.cast.size()==18,"Restart clears handoff and resets18 actors")
        await tap(preview.hud.actions.menu)
        check(await tap(preview.hud.actions.exit),"Exit touch")
        await frames(10)
        check(not is_instance_valid(app._marooning),"Preview teardown")
        # Relaunch the app between formats; each journey starts at the ordinary title UI.
        app.queue_free()
        await frames(4)
        app=load("res://application/game_app.tscn").instantiate()
        root.add_child(app)
        await frames(30)
    app.queue_free()
    await frames(4)
    if DisplayServer.get_name()!="headless": RenderingServer.force_draw(true)
    print("Native UI touch acceptance: ",failures," failures")
    quit(1 if failures else 0)

func capture_app(label: String) -> void:
    if record_dir.is_empty() or DisplayServer.get_name()=="headless": return
    await frames(3)
    RenderingServer.force_draw(true)
    root.get_texture().get_image().save_png(record_dir+"/"+label+".png")

func finish_permanent(count_value: int) -> void:
    await frames(5)
    check(app.screen==SurvivorGameApp.Screen.ARRIVAL and not is_instance_valid(preview),"Real journey reaches permanent arrival summary and releases scene")
    if app.screen!=SurvivorGameApp.Screen.ARRIVAL: return
    check(app._completed_opening.opening_history.dispositions.size()==50,"Real journey preserves all fifty dispositions")
    print("PERMANENT_TOUCH_OPENING bytes=",JSON.stringify(app._completed_opening).length()," events=",app._completed_opening.opening_history.events.size())
    await capture_app("arrival-summary")
    check(await tap(app._actions.begin_day1),"Begin Day 1 touch")
    await frames(30)
    check(app.session!=null and app.locations.camp!=null,"Real journey commits and loads Day 1")
    if app.session==null: return
    var opening: Dictionary=app.session.checkpoint().opening_history
    check(app.locations.camp.inhabitants.size()==18/count_value-1,"Actual tribemates spawned")
    await capture_app("day1-camp")
    var camp := app.locations.camp
    for camera_steering: bool in [false,true]:
        camp.player.camera_relative_steering=camera_steering
        var before := camp.player.position
        var old_yaw := camp.player.yaw
        var home := camp.hud.touch.home()
        var look := Vector2(root.get_visible_rect().size.x*.58,root.get_visible_rect().size.y*.45)
        touch(41,home,true)
        touch(92,look,true)
        for frame in 30:
            drag(41,home+Vector2(0,-camp.hud.touch.radius*.75))
            drag(92,look+Vector2(frame*2.0,0))
            await physics_frame
        touch(41,home,false)
        touch(92,look,false)
        check(camp.player.position.distance_to(before)>.05 and absf(camp.player.yaw-old_yaw)>.01,"Normal two-thumb camp move/orbit in steering mode "+str(camera_steering))
    check(await tap(app._actions.supplies),"Tribal Supplies touch")
    await capture_app("tribal-supplies")
    check(await tap(app._actions.back),"Return to camp touch")
    check(await tap(app._actions.menu),"Save and Main Menu touch")
    await frames(5)
    check(await tap(app._actions.continue),"Continue permanent season touch")
    check(app.session!=null and app.session.checkpoint().opening_history==opening,"Continue retains complete opening")
    check(await tap(app._actions.menu),"Return after Continue")
    check(await tap(app._actions.load),"Load Game touch")
    await capture_app("persisted-season-load")
    check(await tap(app._actions.slot1),"Load saved season touch")
    check(app.session!=null and app.session.checkpoint().opening_history==opening,"Load retains complete opening")
    app._exit_session()
    app.saves.erase(1)
    print("Permanent full touch path: complete")
