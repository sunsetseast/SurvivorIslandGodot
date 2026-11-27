class_name MarooningHUD
extends Control
## The sole HUD owner for every collection, vessel, water and shore state.
var preview: MarooningPreview
var actions: Dictionary={}
var banner: Label
var message: Label
var meter: MarooningTimingMeter
var menu_open := false
var primary: Button
var secondary: Button
var tertiary: Button
var area := Rect2()
var command := ""
var second_command := ""
var third_command := ""
var nearest := ""
func _ready() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter=MOUSE_FILTER_IGNORE
    theme=IslandTheme.create()
    banner=label(25)
    message=label(24)
    meter=MarooningTimingMeter.new()
    meter.simulation=preview.session.race
    add_child(meter)
    primary=button("primary",func() -> void: execute(command))
    secondary=button("secondary",func() -> void: execute(second_command))
    tertiary=button("tertiary",func() -> void: execute(third_command))
    button("menu",func() -> void: menu_open=not menu_open).text="Menu"
    button("exit",preview._exit).text="Exit preview"
    button("restart",func() -> void: preview.call_deferred("restart_scramble")).text="Restart preview"
    layout_safe(Rect2(Vector2.ZERO,get_viewport_rect().size))
func label(font_size: int) -> Label:
    var control := Label.new()
    control.mouse_filter=MOUSE_FILTER_IGNORE
    control.add_theme_font_size_override("font_size",font_size)
    control.add_theme_color_override("font_outline_color",Color.BLACK)
    control.add_theme_constant_override("outline_size",5)
    control.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    control.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    add_child(control)
    return control
func button(id: String, callback: Callable) -> Button:
    var control := Button.new()
    control.clip_text=true
    control.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
    control.add_theme_font_size_override("font_size",27)
    control.pressed.connect(callback)
    add_child(control)
    actions[id]=control
    return control
func layout_safe(rect: Rect2) -> void:
    area=rect
    # 720 design pixels map to >=375 CSS high: 90px targets exceed 44 CSS px.
    var viewport_size := get_viewport_rect().size
    var window_size := Vector2(get_window().size).max(Vector2.ONE)
    if OS.has_feature("web"):
        var browser := JavaScriptBridge.get_interface("window")
        window_size=Vector2(maxf(1,float(browser.innerWidth)),maxf(1,float(browser.innerHeight)))
    var css_factor := maxf(1,viewport_size.y/window_size.y)
    var target := maxf(90,48*css_factor)
    var gap := target+11
    var portrait := area.size.x/area.size.y<.85
    var width := minf(360,area.size.x*.36) if portrait else minf(330,area.size.x*.27)
    for control: Button in actions.values(): control.add_theme_font_size_override("font_size",maxi(27,int(16*css_factor)))
    actions.menu.position=area.position+Vector2(16,12)
    actions.menu.size=Vector2(maxf(155,target*1.6),target)
    banner.position=Vector2(area.position.x+185,area.position.y+12)
    banner.size=Vector2(maxf(200,area.size.x-370),target)
    for index in 3:
        var control: Button=[primary,secondary,tertiary][index]
        control.position=Vector2(area.end.x-width-16,area.end.y-target-16-index*gap)
        control.size=Vector2(width,target)
    message.position=Vector2(area.position.x+maxf(175,area.size.x*.16),area.end.y-target-22)
    message.size=Vector2(maxf(230,area.size.x-width-maxf(175,area.size.x*.16)-44),target+10)
    meter.position=Vector2(area.end.x-width-16,area.end.y-target-16-2*gap-32)
    meter.size=Vector2(width,32)
    for index in 2:
        var control: Button=actions[["exit","restart"][index]]
        control.position=area.position+Vector2(16,target+22+index*gap)
        control.size=Vector2(maxf(270,target*2),target)
func bind_action(control: Button, value: String, text: String) -> String:
    control.visible=not value.is_empty()
    control.text=text
    control.disabled=false
    return value
func update_state() -> void:
    _resolve_state()
    primary.visible=not command.is_empty()
    secondary.visible=not second_command.is_empty()
    tertiary.visible=not third_command.is_empty()
func _resolve_state() -> void:
    if not is_instance_valid(preview.race): return
    var session := preview.session
    var sim := session.scramble
    var race := session.race
    var id := int(preview.configuration.selected)
    var actor: Dictionary=race.actors[id]
    var raft: Dictionary=race.rafts[actor.tribe]
    actions.exit.visible=menu_open
    actions.restart.visible=menu_open or session.state==MarooningSession.State.COMPLETE
    meter.hide()
    command=""
    second_command=""
    third_command=""
    if preview.introducing:
        banner.text="THE MAROONING"
        command=bind_action(primary,"skip","Skip introduction")
        return
    if session.state==MarooningSession.State.READY:
        banner.text="Gather, depart early, or swim"
        command=bind_action(primary,"start","Start marooning")
        return
    if session.state==MarooningSession.State.COUNTDOWN:
        banner.text=str(maxi(1,ceili(session.countdown)))
        primary.hide()
        message.text="Get ready"
        return
    var held := sim.carried(id)
    var tribe_name := str(actor.tribe)
    for tribe: Dictionary in preview.configuration.tribes:
        if tribe.id==actor.tribe: tribe_name=tribe.name
    var remaining := maxi(0,ceili(60-session.elapsed))
    var secured: int=raft.cargo_ids.size()
    banner.text="%s · %02ds collection · %d secured" % [tribe_name,remaining,secured] if sim.eligible(id) and sim.phase==MarooningScramble.Phase.SCRAMBLE_ACTIVE else "%s · %s" % [tribe_name,str(raft.state).capitalize()]
    if session.state==MarooningSession.State.COMPLETE:
        primary.hide()
        var reward_text := "won" if race.reward.tribe==actor.tribe else ("unclaimed" if race.reward.status=="unclaimed" else "claimed by a rival")
        banner.text="MAROONING COMPLETE · Fishing reward: "+reward_text
        var rivals_pending := 0
        for other_tribe: Dictionary in preview.configuration.tribes:
            if other_tribe.id==actor.tribe: continue
            var pending := false
            for other_id in other_tribe.members: pending=pending or not race.actors[int(other_id)].arrived
            rivals_pending+=int(pending)
        message.text="Your tribe and %d cargo items reached shore. %d rival tribes unresolved at this boundary.\nPreview boundary · Day 1 continues in Phase 4D.4. Walk, look, restart or exit." % [raft.delivered_ids.size(),rivals_pending]
        return
    if preview.race.transitions.has(id) or race.pending.has(id):
        primary.hide()
        message.text="Jumping to water" if preview.race.transitions.has(id) else "Climbing aboard your moving raft"
        return
    if not actor.raft.is_empty():
        if raft.state=="moored":
            command=bind_action(primary,"launch","Let's Go")
            second_command=bind_action(secondary,"jump_off","Disembark")
            message.text="Crew %d/%d · leaving locks your basket. Crew decides after encouragement." % [raft.crew.size(),raft.capacity]
        elif raft.state=="underway":
            command=bind_action(primary,"paddle","Paddle") if actor.paddling else bind_action(primary,"rest","Begin paddling")
            second_command=bind_action(secondary,"rest","Rest") if actor.paddling else ""
            third_command=bind_action(tertiary,"jump_off","Jump off")
            meter.visible=actor.paddling
            banner.text="%.1f m/s · Crew %d · Sync %d%%" % [raft.speed,raft.crew.size(),float(raft.sync)*100]
            message.text="Tap at the center · "+race.feedback
        else:
            command=bind_action(primary,"jump_off","Disembark")
            message.text="Landing · bring your cargo ashore"
        return
    if actor.place=="deck":
        nearest=""
        var best := INF
        if sim.eligible(id) and held.is_empty():
            for item: Dictionary in sim.items.values():
                var action := "steal" if item.state==MarooningScramble.State.CARRIED else "pickup"
                if not sim.valid(id,action,item.id) or not preview.scramble.accessible(id,action,item.id): continue
                var point: Vector3=sim.actors[item.actor].position if action=="steal" else item.position
                var gap: float=preview.player.position.distance_to(point)
                if gap<best:
                    best=gap
                    nearest=item.id
                    command=action
        if not nearest.is_empty():
            bind_action(primary,command,("Steal " if command=="steal" else "Pick up ")+str(sim.definitions[sim.items[nearest].type].name))
        elif race.can_board(id): command=bind_action(primary,"board","Board raft")
        else: command=bind_action(primary,"jump_deck","Jump into water")
        var gate: Vector3=preview.routes[actor.tribe].deck_access
        if command=="jump_deck": primary.disabled=MarooningRace.planar(preview.player.position,gate)>4.2 or absf(preview.player.position.x)<2.8
        if not held.is_empty(): second_command=bind_action(secondary,"drop","Drop")
        if command!="jump_deck": third_command=bind_action(tertiary,"jump_deck","Jump into water")
        if not third_command.is_empty(): tertiary.disabled=MarooningRace.planar(preview.player.position,gate)>4.2 or absf(preview.player.position.x)<2.8
        message.text=(str(sim.definitions[sim.items[held].type].name)+" · carry to your colored basket" if not held.is_empty() else (("Near "+str(sim.definitions[sim.items[nearest].type].name)) if not nearest.is_empty() else "Hands free · use your tribe's open side ramp to leave"))+"\nJump commits to water travel. "+preview.race.feedback
        if sim.pending.has(id):
            primary.disabled=true
            message.text="Loading at your basket... stay close"
        return
    if actor.arrived or (preview.player.position.y>.25 and preview.player.position.z>160):
        primary.hide()
        var arrived := 0
        var total := 0
        for other: Dictionary in race.actors.values():
            if other.tribe==actor.tribe:
                total+=1
                arrived+=int(other.arrived)
        message.text="On shore · regrouping %d/%d · cargo %d/%d\nWalk and look while your tribe arrives." % [arrived,total,raft.delivered_ids.size(),raft.cargo_ids.size()]
        return
    if not race.reward_resolved() and actor.position.distance_to(preview.layout.reward)<=4.5: command=bind_action(primary,"claim_reward","Claim fishing reward")
    elif race.can_board(id): command=bind_action(primary,"board","Board raft")
    else: primary.hide()
    var objective := "Fishing reward" if not race.reward_resolved() else "Your shore"
    message.text="%s · %dm\n%s" % [objective,ceili(preview.player.position.distance_to(race.actor_objective(id))),preview.race.feedback]
func execute(action: String) -> void:
    var id := int(preview.configuration.selected)
    match action:
        "skip": preview.finish_intro()
        "start": preview.session.start()
        "launch": preview.session.request_launch(id)
        "paddle": preview.session.race.stroke(id)
        "rest": preview.race.toggle_rest()
        "jump_off": preview.race.jump_off()
        "jump_deck": preview.race.jump_deck(id)
        "board": preview.race.board_actor(id)
        "claim_reward": preview.session.race.claim(id,preview.race.access(id,"claim"))
        "pickup", "steal":
            if not nearest.is_empty(): preview.session.scramble.request(id,action,nearest,preview.scramble.accessible(id,action,nearest))
        "drop": preview.scramble.drop()
