extends SceneTree
## Full ordinary UI pilot. Only touch events drive the selected contestant.
var app: SurvivorGameApp
var preview: MarooningPreview
var failures := 0
var captures := {}
var move_down := false
var record_dir := ""
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
    preview.hud.update_state()
    for pair: Array in [[preview.hud.command,preview.hud.primary],[preview.hud.second_command,preview.hud.secondary],[preview.hud.third_command,preview.hud.tertiary]]:
        if pair[0]==command: return await tap(pair[1])
    return false
func capture(label: String,view := "follow") -> void:
    if record_dir.is_empty() or DisplayServer.get_name()=="headless": return
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
        if preview.session.elapsed>=end: break
    touch(41,home,false)
    move_down=false
    await frames(2)
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
    check(await tap(app._actions.marooning),"Private marooning touch")
    await frames(10)
    if not is_instance_valid(app._marooning): return false
    preview=app._marooning
    check(preview.session.elapsed==0,"Intro does not consume gameplay time")
    check(await action("skip"),"Skip introduction touch")
    check(await action("start"),"Start touch")
    await frames(190)
    return preview.session.state==MarooningSession.State.ACTIVE
func run() -> void:
    record_dir=OS.get_environment("MAROONING_CAPTURE_DIR")
    root.size=Vector2i(956,440)
    root.content_scale_size=Vector2i(1280,720)
    app=load("res://application/game_app.tscn").instantiate()
    root.add_child(app)
    await frames(30)
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
        await walk(gate,.4,15)
        var jumped := await action("jump_deck")
        if not jumped:
            await walk(gate+Vector3(0,0,.65),.3,8)
            jumped=await action("jump_deck")
        check(jumped and preview.race.transitions.has(selected),"Real open-side jump touch "+str(count_value))
        await frames(100)
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
        var paddles := 0
        var deadline := preview.session.elapsed+300
        while preview.session.state!=MarooningSession.State.COMPLETE and preview.session.elapsed<deadline:
            var raft: Dictionary=preview.session.race.rafts[state.tribe]
            if not state.raft.is_empty():
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
                var goal := preview.session.race.actor_objective(selected)
                await walk(goal,1.5,3)
                if preview.hud.command=="claim_reward": await action("claim_reward")
            await frames(3)
        check(preview.session.state==MarooningSession.State.COMPLETE,"Full touch journey reaches summary "+str(count_value))
        check(preview.has_meta("marooning_result"),"Version2 transient result")
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
