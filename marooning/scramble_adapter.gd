class_name MarooningScrambleAdapter
extends Node
var preview: MarooningPreview
var simulation := MarooningScramble.new()
var visuals: Dictionary = {}
var flights: Dictionary = {}
var previous_states: Dictionary = {}
var targets: Dictionary = {}
var agents: Dictionary = {}
var brain_elapsed := 0.0
var brain_index := 0
var hud: Label
var action_button: Button
var drop_button: Button
var steal_button: Button
var steal_target := ""
var start_button: Button
var restart_button: Button
var contextual := ""
var nearest := ""
var finished := false
var last_feedback := -1.0
var stalled: Dictionary = {}
var last_positions: Dictionary = {}
var rejected: Dictionary = {}
var traffic := MarooningDeckTraffic.new()
var station_visuals: Dictionary = {}
var cargo_slots: Dictionary = {}
var carry_attachments: Dictionary = {}
var guidance: Label
var target_marker: MeshInstance3D
var base_configuration: Dictionary

func _ready() -> void:
    var roster := {}
    var stations := {}
    for i in preview.configuration.tribes.size():
        var tribe: Dictionary = preview.configuration.tribes[i]
        stations[tribe.id] = preview.layout.collection_centres[i]
        var station := MarooningCollectionStation.new()
        station.build(tribe)
        station.position = stations[tribe.id]
        preview.add_child(station)
        station_visuals[tribe.id] = station
    for id: int in preview.cast:
        var actor: Node3D = preview.cast[id]
        roster[id] = {"position":actor.position,"tribe":actor.get_meta("tribe_id"),"attributes":preview.catalog.get_by_id(id).attributes}
        if actor != preview.player:
            var agent := NavigationAgent3D.new()
            agent.path_desired_distance = .5
            agent.path_height_offset = .3
            agent.target_desired_distance = .8
            actor.add_child(agent)
            agents[id] = agent
    simulation.configure(preview.configuration,roster,preview.layout.supply_anchors(),stations,[Vector3(-3.1,preview.layout.deck_y,8),Vector3(3.1,preview.layout.deck_y,8)])
    preview.layout.arrange_supplies(simulation.items,simulation.seed_value)
    for tribe: String in stations:
        var centre: Vector3 = stations[tribe]
        var approaches: Array[Vector3] = []
        for offset: float in [-1.2,0.0,1.2]:
            approaches.append(centre+Vector3(-signf(centre.x)*1.05,0,offset))
        simulation.unloading[tribe] = approaches
    traffic.bind(self)
    for id: String in simulation.items:
        var visual := MarooningSupplyVisual.new()
        visual.build(simulation.items[id].type)
        preview.add_child(visual)
        visual.position = simulation.items[id].position
        visuals[id] = visual
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := VBoxContainer.new()
    panel.theme = IslandTheme.create()
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    panel.offset_left = -220
    panel.offset_right = 220
    panel.offset_top = 12
    panel.offset_bottom = 92
    layer.add_child(panel)
    hud = Label.new()
    hud.add_theme_font_size_override("font_size",28)
    hud.add_theme_color_override("font_outline_color",Color.BLACK)
    hud.add_theme_constant_override("outline_size",5)
    hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    panel.add_child(hud)
    guidance = Label.new()
    guidance.add_theme_font_size_override("font_size",26)
    guidance.mouse_filter = Control.MOUSE_FILTER_IGNORE
    guidance.custom_minimum_size = Vector2(360,90)
    guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    guidance.add_theme_color_override("font_outline_color",Color.BLACK)
    guidance.add_theme_constant_override("outline_size",5)
    layer.add_child(guidance)
    start_button = button(panel,"Start Supply Scramble · 120s",start)
    action_button = button(panel,"Pick Up",interact)
    drop_button = button(panel,"Drop",drop)
    steal_button = button(panel,"Steal",steal)
    steal_button.hide() # Compatibility reference; only primary contextual action is shown.
    restart_button = button(panel,"Restart preview",restart)
    restart_button.hide()
    action_button.hide()
    drop_button.hide()
    steal_button.hide()

func button(parent: Node, text: String, action: Callable) -> Button:
    var control := Button.new()
    control.text = text
    control.custom_minimum_size.y = 90
    control.add_theme_font_size_override("font_size",26)
    control.pressed.connect(action)
    parent.add_child(control)
    if text in ["Pick Up","Drop","Steal"]:
        control.reparent(parent.get_parent())
        control.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
        control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        control.custom_minimum_size.y = 90
        control.add_theme_font_size_override("font_size",28)
        control.offset_left = -370
        control.offset_right = -18
        control.offset_top = {"Pick Up":-214,"Drop":-108,"Steal":-314}[text]
        control.offset_bottom = {"Pick Up":-118,"Drop":-18,"Steal":-218}[text]
    return control

func start() -> void:
    if preview.introducing:
        return
    simulation.ready()
    simulation.start()
    start_button.hide()
    preview.subtitle.text = "Gather supplies for your tribe! Carry one item; take it to your tribe’s colored basket.\nDeposit is automatic. Drop to change cargo; stealing is optional."

func restart() -> void:
    preview.call_deferred("restart_scramble")

func accessible(actor: int, action: String, id: String) -> bool:
    if action not in ["pickup","steal","load"]:
        return true
    var body: Node3D = preview.cast[actor]
    var from := body.global_position + Vector3.UP * .5
    var to: Vector3 = visuals[id].target_point() if action=="steal" else simulation.items[id].position+Vector3.UP*.3
    if action == "load":
        var approaches: Array = simulation.unloading.get(simulation.actors[actor].tribe,[simulation.stations[simulation.actors[actor].tribe]])
        var closest: Vector3 = approaches[0]
        for point: Vector3 in approaches:
            if body.position.distance_to(point) < body.position.distance_to(closest): closest = point
        to = closest + Vector3.UP*.5
    var query := PhysicsRayQueryParameters3D.create(from,to,1)
    return preview.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(delta: float) -> void:
    if simulation.suspended:
        return
    for id: int in preview.cast:
        simulation.actors[id].position = preview.cast[id].position
    traffic.update_player()
    simulation.advance(delta,accessible)
    if simulation.phase == MarooningScramble.Phase.SCRAMBLE_ACTIVE:
        brain_elapsed += delta
        if brain_elapsed >= .05:
            brain_elapsed = 0
            var ids := agents.keys()
            for iteration in 2:
                decide(ids[brain_index % ids.size()])
                brain_index += 1
        for id: int in agents:
            traffic.step(id,delta)
        preview.player.movement_speed_multiplier = simulation.multiplier(int(preview.configuration.selected))
    elif simulation.phase == MarooningScramble.Phase.SCRAMBLE_COMPLETE and not finished:
        update_visuals(delta)
        detach_cargo_for_departure()
        finished = true
        if target_marker != null: target_marker.hide()
        action_button.hide()
        drop_button.hide()
        hud.hide()
        steal_button.hide()
        preview.set_meta("scramble_result",simulation.result(preview.routes))
        preview.race.begin()
    update_guidance()
    if not finished:
        update_visuals(delta)
        update_hud()

func decide(id: int) -> void:
    if simulation.pending.has(id):
        return
    var held := simulation.carried(id)
    var actor: Node3D = preview.cast[id]
    var agent: NavigationAgent3D = agents[id]
    if not held.is_empty():
        traffic.target(id,traffic.unloading_goal(id),"carrying")
        targets[id] = held
        return
    if traffic.slots.has(id):
        traffic.release(id)
        targets.erase(id)
        traffic.target(id,actor.position+Vector3(-signf(actor.position.x)*.8,0,1.0),"clearing")
        return
    if traffic.intents.get(id,"") == "clearing" and MarooningDeckTraffic.planar(actor.position,traffic.goals[id]) > .3:
        return
    if targets.has(id):
        var target: String = targets[id]
        if simulation.valid(id,"pickup",target):
            simulation.request(id,"pickup",target,accessible(id,"pickup",target))
            return
        if simulation.items[target].state in [MarooningScramble.State.ABOARD,MarooningScramble.State.DROPPED]:
            return
        targets.erase(id)
    # Theft is rare and personality/value gated; collection remains predominant.
    if simulation.rating(id,"risk") + simulation.rating(id,"aggression") > 14:
        for item: Dictionary in simulation.items.values():
            if item.state == MarooningScramble.State.CARRIED and simulation.valid(id,"steal",item.id) and simulation.definitions[item.type].category in ["tool","food"]:
                if simulation.request(id,"steal",item.id,accessible(id,"steal",item.id)):
                    return
    if last_positions.has(id) and actor.position.distance_to(last_positions[id]) < .15 and targets.has(id):
        stalled[id] = int(stalled.get(id,0)) + 1
        if stalled[id] > 12:
            rejected[str(id) + ":" + str(targets[id])] = simulation.elapsed + 8
            targets.erase(id)
            stalled[id] = 0
    else:
        stalled[id] = 0
    last_positions[id] = actor.position
    var best := ""
    var best_score := -INF
    var secured: Array[Dictionary] = []
    for item: Dictionary in simulation.items.values():
        if item.state == MarooningScramble.State.SECURED and item.tribe == simulation.actors[id].tribe:
            secured.append(item)
    for item: Dictionary in simulation.items.values():
        if item.state not in [MarooningScramble.State.ABOARD,MarooningScramble.State.DROPPED]:
            continue
        if float(rejected.get(str(id) + ":" + str(item.id),0)) > simulation.elapsed:
            continue
        var definition: Dictionary = simulation.definitions[item.type]
        var distance: float = actor.position.distance_to(item.position)
        var utility := 8.0
        for tag: String in definition.tags:
            utility += simulation.rating(id,tag) * .3
        for own: Dictionary in secured:
            if own.type == item.type:
                utility *= .6
        var competition := 0.0
        for other: int in targets:
            if other != id and targets[other] == item.id:
                competition += .9 + simulation.rating(id,"awareness") * .1
        utility += simulation.rating(id,"campcraft") * .1 + simulation.rating(id,"leader") * .08
        utility -= maxf(0, float(definition.weight) - simulation.rating(id,"strength") * .3) * .4
        if simulation.duration - simulation.elapsed < distance / 2 + 5:
            utility *= .15 + simulation.rating(id,"risk") * .02
        var variation := float(hash("%s:%s:%s" % [simulation.seed_value,id,item.id]) % 1000) / 1000.0
        var score := utility / (2 + distance / simulation.multiplier(id)) - competition + variation * .7
        if score > best_score:
            best = item.id
            best_score = score
    if best.is_empty():
        targets.erase(id)
        # No reachable supplies: leave the collection lanes open, retain participation.
        var centre: Vector3 = simulation.stations[simulation.actors[id].tribe]
        traffic.target(id,traffic.parking_goal(id),"waiting")
    else:
        var destination: Vector3 = simulation.items[best].position
        var approach := destination
        var best_distance := INF
        for offset: Vector3 in [Vector3(-1,0,0),Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,0,1),Vector3.ZERO]:
            var point := destination+offset
            var path := NavigationServer3D.map_get_path(agent.get_navigation_map(),actor.position,point,true)
            if path.is_empty() or MarooningDeckTraffic.planar(path[path.size()-1],point)>.4: continue
            var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.5,destination+Vector3.UP*.3,1)
            if not preview.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
            var score := actor.position.distance_to(point)
            if score<best_distance:
                best_distance = score
                approach = point
        if best_distance == INF:
            rejected[str(id)+":"+best] = simulation.elapsed+8
            targets.erase(id)
            return
        targets[id] = best
        traffic.target(id,approach,"approaching")

func update_visuals(delta: float) -> void:
    var counts := {}
    for id: String in simulation.items:
        var item: Dictionary = simulation.items[id]
        var visual: Node3D = visuals[id]
        if item.state!=MarooningScramble.State.CARRIED and visual.get_parent()!=preview:
            visual.reparent(preview,true)
            visual.rotation=Vector3(0,visual.global_rotation.y,0)
            visual.scale=Vector3.ONE
        if item.state == MarooningScramble.State.FLOATING and previous_states.get(id,-1) != item.state:
            flights[id] = {"from":visual.position,"time":0.0}
        previous_states[id] = item.state
        if flights.has(id):
            flights[id].time += delta
            var progress := minf(float(flights[id].time)/.65,1)
            visual.position = (flights[id].from as Vector3).lerp(item.position,progress) + Vector3.UP * sin(progress*PI)*1.5
            if progress >= 1:
                flights.erase(id)
            continue
        if item.state == MarooningScramble.State.CARRIED:
            attach_carried(visual,item)
        elif item.state == MarooningScramble.State.SECURED:
            var tribe: String = item.tribe
            if not cargo_slots.has(id):
                var occupied := 0
                for cargo_id: String in cargo_slots:
                    if simulation.items[cargo_id].tribe == tribe: occupied += 1
                cargo_slots[id] = occupied
            var index := int(cargo_slots[id])
            var raft_index := 0
            for i in preview.configuration.tribes.size():
                if preview.configuration.tribes[i].id == tribe:
                    raft_index = i
            var overflow := index>=12
            var slot := index-12 if overflow else index
            visual.position = simulation.stations[tribe] + Vector3((slot%2-.5)*.36,(.16 if overflow else .35)+(slot/4)*.35,(2.1 if overflow else 0.0)+(slot/2%2-.5)*.85)
            visual.scale = Vector3.ONE*.65
        else:
            visual.position = item.position

func update_hud() -> void:
    var id := int(preview.configuration.selected)
    var held := simulation.carried(id)
    var tribe: String = simulation.actors[id].tribe
    var secured := 0
    for item: Dictionary in simulation.items.values():
        if item.state == MarooningScramble.State.SECURED and item.tribe == tribe:
            secured += 1
    hud.text = "%03d s · %s · Secured %d\n%s" % [ceili(simulation.duration-simulation.elapsed),tribe,secured,"Hands free" if held.is_empty() else simulation.definitions[simulation.items[held].type].name]
    if simulation.phase != MarooningScramble.Phase.SCRAMBLE_ACTIVE:
        return
    for event: Dictionary in simulation.events:
        if event.actor == id and float(event.elapsed) > last_feedback:
            preview.subtitle.text = ("%s secured" % simulation.definitions[event.type].name if event.action == "load" and event.outcome == "success" else "%s · %s" % [simulation.definitions[event.type].name,{"success":"Done","failed":"Interrupted or moved out of reach","expired":"Time is up","attempted":"Stealing… stay close"}.get(event.outcome,event.outcome)])
            last_feedback = event.elapsed
    steal_button.hide()
    var old := nearest
    nearest = ""
    contextual = ""
    var best := -INF
    if simulation.pending.has(id):
        nearest = simulation.pending[id].item
        contextual = simulation.pending[id].action
    elif held.is_empty():
        var camera := preview.get_viewport().get_camera_3d()
        var facing := -camera.global_basis.z
        for item: Dictionary in simulation.items.values():
            var action := "steal" if item.state == MarooningScramble.State.CARRIED else "pickup"
            if not simulation.valid(id,action,item.id) or not accessible(id,action,item.id): continue
            var point: Vector3 = simulation.actors[item.actor].position if action == "steal" else item.position
            var difference: Vector3 = point-preview.player.position
            var visible_point: Vector3 = visuals[item.id].target_point() if action=="steal" else point+Vector3.UP*.2
            if camera.is_position_behind(visible_point): continue
            var bearing := camera.global_position.direction_to(visible_point)
            var score := facing.dot(bearing)*12.0 - difference.length()*.4 + (.15 if item.id == old else 0.0) + (.25 if action=="pickup" else 0.0)
            if score > best:
                nearest = item.id
                contextual = action
                best = score
    action_button.visible = not nearest.is_empty() and contextual in ["pickup","steal"]
    action_button.text = ("Steal " if contextual == "steal" else "Pick Up ") + (simulation.definitions[simulation.items[nearest].type].name if not nearest.is_empty() else "")
    if contextual == "steal" and not nearest.is_empty():
        var victim := int(simulation.items[nearest].actor)
        if victim != 0: hud.tooltip_text = str(preview.catalog.get_by_id(victim).name)
    action_button.disabled = simulation.pending.has(id)
    drop_button.visible = not held.is_empty()
    drop_button.disabled = simulation.pending.has(id)
    if target_marker == null:
        target_marker = MeshInstance3D.new()
        var ring := TorusMesh.new()
        ring.inner_radius = .28
        ring.outer_radius = .33
        ring.rings = 24
        ring.ring_segments = 6
        target_marker.mesh = ring
        target_marker.material_override = MarooningBay.material(Color("f4d18b"))
        preview.add_child(target_marker)
    target_marker.visible = not nearest.is_empty() and held.is_empty()
    if target_marker.visible:
        var item: Dictionary = simulation.items[nearest]
        target_marker.position = (simulation.actors[item.actor].position if item.state == MarooningScramble.State.CARRIED else item.position) + Vector3.UP*.06
    var all_secured := 0
    for item: Dictionary in simulation.items.values(): all_secured += int(item.state==MarooningScramble.State.SECURED)
    var seconds := maxi(0,ceili(simulation.duration-simulation.elapsed))
    var tribe_name := tribe
    for row: Dictionary in preview.configuration.tribes:
        if row.id == tribe: tribe_name = row.name
    hud.text = "%d:%02d · %s · %d secured\n%s" % [seconds/60,seconds%60,tribe_name,secured,"Hands free · aim at a supply" if held.is_empty() else simulation.definitions[simulation.items[held].type].name+" → your basket · automatic deposit"]
    if all_secured==50: hud.text += "\nAll supplies secured · prepare for the bow exit"
    if contextual == "steal" and not nearest.is_empty():
        var victim := int(simulation.items[nearest].actor)
        if victim != 0: hud.text += "\nTarget: " + str(preview.catalog.get_by_id(victim).name)
    if simulation.pending.has(id):
        var command: Dictionary = simulation.pending[id]
        var progress := clampf((simulation.elapsed-float(command.started))/maxf(.01,float(command.at)-float(command.started)),0,1)
        hud.text += "\n%s %d%%" % ["Depositing…" if command.action == "load" else "Working…",int(progress*100)]

func update_guidance() -> void:
    var id := int(preview.configuration.selected)
    var sim := simulation
    var held := sim.carried(id)
    guidance.visible = not held.is_empty() or finished
    if not guidance.visible: return
    var tribe: String = sim.actors[id].tribe
    var goal: Vector3 = sim.stations[tribe]+Vector3.UP
    var title := "Your collection basket"
    if finished:
        if preview.race.simulation.phase == MarooningRace.Phase.ARRIVAL_COMPLETE:
            guidance.hide()
            return
        var race := preview.race.simulation
        goal = Vector3(0,preview.layout.deck_y,8) if preview.player.position.z<18 and preview.player.position.y>.4 else race.boarding_point(tribe)
        title = "Bow exit" if goal.z==8 else "Your raft · stern access"
        if not race.actors[id].raft.is_empty() or not race.reward.tribe.is_empty():
            goal = race.objective(tribe)
            title = "Fishing reward" if race.reward.tribe.is_empty() else "Your shore"
    var camera := preview.get_viewport().get_camera_3d()
    var size := preview.get_viewport().get_visible_rect().size
    var point := camera.unproject_position(goal)
    var indicator := "↓"
    if camera.is_position_behind(goal):
        var left := camera.to_local(goal).x<0
        point = Vector2(155 if left else size.x-380,size.y*.3)
        indicator = "← Turn" if left else "Turn →"
    elif point.x<155: indicator = "←"
    elif point.x>size.x-380: indicator = "→"
    elif point.y<95: indicator = "↑"
    point.x = clampf(point.x,155,size.x-380)
    point.y = clampf(point.y,95,size.y-150)
    guidance.position = point
    guidance.text = "%s %s · %dm" % [indicator,title,ceili(preview.player.position.distance_to(goal))]

func interact() -> void:
    if not nearest.is_empty() and not contextual.is_empty():
        var accepted := simulation.request(int(preview.configuration.selected),contextual,nearest,accessible(int(preview.configuration.selected),contextual,nearest))
        preview.subtitle.text = "Stay close…" if accepted else "Unavailable or contested · move closer or wait"
func drop() -> void:
    var id := int(preview.configuration.selected)
    simulation.request(id,"drop",simulation.carried(id))

func steal() -> void:
    if not steal_target.is_empty():
        var id := int(preview.configuration.selected)
        var accepted := simulation.request(id,"steal",steal_target,accessible(id,"steal",steal_target))
        preview.subtitle.text = "Theft attempted · stay close until completion" if accepted else "Theft unavailable · move closer or wait"

func review_state() -> Dictionary:
    var rows: Array = []
    for item: Dictionary in simulation.items.values():
        var point: Vector3 = simulation.actors[item.actor].position if item.state == MarooningScramble.State.CARRIED else item.position
        rows.append({"id":item.id,"type":item.type,"state":item.state,"actor":item.actor,"position":[point.x,point.y,point.z]})
    var id := int(preview.configuration.selected)
    var station: Vector3 = simulation.stations[simulation.actors[id].tribe]
    return {"items":rows,"carried":simulation.carried(id),"target":nearest,"action":contextual,"basket":[station.x,station.y,station.z],"pending":simulation.pending.get(id,{}),"contributions":simulation.contributions[id]}

func layout_actions(area: Rect2) -> void:
    var banner := hud.get_parent() as Control
    banner.offset_top=area.position.y+12
    var size := preview.get_viewport().get_visible_rect().size
    var right := maxf(18,size.x-area.end.x+18)
    var bottom := maxf(18,size.y-area.end.y+18)
    for control: Button in [action_button,drop_button,steal_button]:
        control.offset_left=-right-352
        control.offset_right=-right
    action_button.offset_top=-bottom-196
    action_button.offset_bottom=-bottom-100
    drop_button.offset_top=-bottom-90
    drop_button.offset_bottom=-bottom
    steal_button.offset_top=-bottom-296
    steal_button.offset_bottom=-bottom-200

func attach_carried(visual: MarooningSupplyVisual,item: Dictionary) -> void:
    var actor: CampHumanoidMotor=preview.cast[item.actor]
    var skeleton: Skeleton3D=actor.presentation.skeleton
    var bone := skeleton.find_bone("hand_r")
    if bone<0:
        visual.global_position=actor.position+Vector3(-.4,.95,.1).rotated(Vector3.UP,actor.travel_heading)
        return
    if not carry_attachments.has(item.actor):
        var attachment := BoneAttachment3D.new()
        attachment.bone_name=skeleton.get_bone_name(bone)
        skeleton.add_child(attachment)
        carry_attachments[item.actor]=attachment
    var parent: BoneAttachment3D=carry_attachments[item.actor]
    if visual.get_parent()==parent: return
    var hand := skeleton.global_transform*skeleton.get_bone_global_pose(bone)
    var grip := MarooningSupplyVisual.carry_grip(item.type)
    var basis := hand.basis.inverse()*Basis(Vector3.UP,actor.travel_heading)*Basis.from_euler(grip.rotation)
    visual.reparent(parent,false)
    visual.transform=Transform3D(basis,-(basis*(grip.point as Vector3)))

func detach_cargo_for_departure() -> void:
    for id: String in simulation.items:
        var item: Dictionary=simulation.items[id]
        var visual: Node3D=visuals[id]
        if visual.get_parent()!=preview: visual.reparent(preview,true)
        if item.state==MarooningScramble.State.CARRIED:
            visual.position=preview.cast[item.actor].position
            visual.rotation=Vector3(0,visual.rotation.y,0)
            visual.scale=Vector3.ONE
