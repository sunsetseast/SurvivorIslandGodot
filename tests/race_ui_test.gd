extends SceneTree
var failures := 0
func check(value: bool,message: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
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
    preview.session.start(false)
    preview.set_physics_process(false)
    var actor: Dictionary=preview.session.race.actors[18]
    var raft: Dictionary=preview.session.race.rafts[actor.tribe]
    for viewport_size: Vector2i in [Vector2i(956,440),Vector2i(812,375),Vector2i(844,390),Vector2i(390,844)]:
        root.size=viewport_size
        root.content_scale_size=Vector2i(1280,720)
        for frame in 5: await process_frame
        var bounds := preview.get_viewport().get_visible_rect()
        for state_name: String in ["deck","moored","underway","swimming","shore","summary"]:
            actor.raft=actor.tribe if state_name in ["moored","underway"] else ""
            actor.place="aboard" if not actor.raft.is_empty() else state_name
            actor.arrived=state_name=="shore"
            raft.state=state_name
            preview.session.state=MarooningSession.State.COMPLETE if state_name=="summary" else MarooningSession.State.ACTIVE
            preview.hud.update_state()
            for button: Button in preview.hud.actions.values():
                if not button.visible: continue
                var css := button.get_global_rect().size*Vector2(viewport_size)/bounds.size
                check(css.y>=44,"44CSS height "+state_name+" "+str(viewport_size)+" "+str(css))
                check(bounds.encloses(button.get_global_rect()),"Visible action fits "+state_name+" "+button.text+" rect="+str(button.get_global_rect())+" area="+str(preview.hud.area))
            check(preview.hud.meter.visible==(state_name=="underway"),"Only underway owns paddle meter")
            if state_name=="moored": check(preview.hud.primary.text=="Let's Go","Moored encouragement replaces paddle/rest")
            if state_name=="shore": check(not preview.hud.primary.visible,"No obsolete shore action")
        var safe := Rect2(bounds.position+Vector2(100,30),bounds.size-Vector2(200,75))
        preview.touch.safe=safe
        preview._layout_hud_safe()
        preview.session.state=MarooningSession.State.ACTIVE
        actor.raft=actor.tribe
        raft.state="underway"
        preview.hud.update_state()
        for button: Button in preview.hud.actions.values():
            if button.visible: check(safe.encloses(button.get_global_rect()),"Safe bounds "+button.text)
        print("STATE_HUD ",viewport_size," bounds=",bounds)
    # A held native touch must survive HUD refreshes until release.
    actor.paddling=true
    preview.hud.update_state()
    var point := preview.hud.secondary.get_global_rect().get_center()
    var event := InputEventScreenTouch.new()
    event.index=772
    event.position=point
    event.pressed=true
    root.push_input(event,true)
    for frame in 5: await process_frame
    event=event.duplicate()
    event.pressed=false
    root.push_input(event,true)
    for frame in 3: await process_frame
    check(not actor.paddling,"Held secondary touch fires after multiple HUD refreshes")
    preview.queue_free()
    await process_frame
    print("Race UI: ",failures," failures")
    quit(1 if failures else 0)
