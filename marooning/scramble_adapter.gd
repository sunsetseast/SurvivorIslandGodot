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
var start_button: Button
var restart_button: Button
var contextual := ""
var nearest := ""
var finished := false
var stalled: Dictionary = {}
var last_positions: Dictionary = {}
var rejected: Dictionary = {}
var base_configuration: Dictionary

func _ready() -> void:
    var roster := {}
    var stations := {}
    for i in preview.configuration.tribes.size():
        var tribe: Dictionary = preview.configuration.tribes[i]
        # Loading is handled at the rail alongside the actual raft, never at distance.
        stations[tribe.id] = Vector3(-3.1 if i == 0 else 3.1, preview.layout.deck_y, -5.8 if i < 2 else 5)
        var label := Label3D.new()
        label.text = tribe.name + " · LOAD"
        label.position = stations[tribe.id] + Vector3.UP * 1.6
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.modulate = Color(tribe.color)
        preview.add_child(label)
    for id: int in preview.cast:
        var actor: Node3D = preview.cast[id]
        roster[id] = {"position":actor.position,"tribe":actor.get_meta("tribe_id"),"attributes":preview.catalog.get_by_id(id).attributes}
        if actor != preview.player:
            var agent := NavigationAgent3D.new()
            agent.path_desired_distance = .25
            agent.target_desired_distance = .8
            actor.add_child(agent)
            agents[id] = agent
    var anchors: Array[Vector3] = []
    for row in 13:
        for x: float in [-2.65,-1.35,1.35,2.65]:
            anchors.append(Vector3(x,preview.layout.deck_y,-4.5 + row * .98))
    simulation.configure(preview.configuration,roster,anchors,stations,[Vector3(-3.1,preview.layout.deck_y,8),Vector3(3.1,preview.layout.deck_y,8)])
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
    panel.position = Vector2(350,12)
    layer.add_child(panel)
    hud = Label.new()
    hud.add_theme_color_override("font_outline_color",Color.BLACK)
    hud.add_theme_constant_override("outline_size",5)
    panel.add_child(hud)
    start_button = button(panel,"Start Supply Scramble · 120s",start)
    action_button = button(panel,"Pick Up",interact)
    drop_button = button(panel,"Drop",drop)
    restart_button = button(panel,"Restart preview",restart)
    restart_button.hide()
    action_button.hide()
    drop_button.hide()

func button(parent: Node, text: String, action: Callable) -> Button:
    var control := Button.new()
    control.text = text
    control.pressed.connect(action)
    parent.add_child(control)
    return control

func start() -> void:
    if preview.introducing:
        return
    simulation.ready()
    simulation.start()
    start_button.hide()
    preview.subtitle.text = "Gather supplies for your tribe! Carry one item; load at your tribe’s rail station.\nThrow at either bow opening. Floating cargo is unsecured."

func restart() -> void:
    preview.call_deferred("restart_scramble")

func accessible(actor: int, action: String, id: String) -> bool:
    if action != "pickup":
        return true
    var body: Node3D = preview.cast[actor]
    var from := body.global_position + Vector3.UP * .5
    var to: Vector3 = simulation.items[id].position + Vector3.UP * .3
    var query := PhysicsRayQueryParameters3D.create(from,to,1)
    return preview.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(delta: float) -> void:
    if simulation.suspended:
        return
    for id: int in preview.cast:
        simulation.actors[id].position = preview.cast[id].position
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
            var actor: CampHumanoidMotor = preview.cast[id]
            var direction := Vector3.ZERO
            if targets.has(id) and not simulation.pending.has(id):
                var agent: NavigationAgent3D = agents[id]
                if not agent.is_navigation_finished():
                    direction = actor.position.direction_to(agent.get_next_path_position())
                    direction.y = 0
            actor.movement_speed_multiplier = simulation.multiplier(id) * clampf(.8 + simulation.rating(id,"speed") * .04,.84,1.2)
            actor.walk_direction(direction,true,delta)
        preview.player.movement_speed_multiplier = simulation.multiplier(int(preview.configuration.selected))
    elif simulation.phase == MarooningScramble.Phase.SCRAMBLE_COMPLETE and not finished:
        finished = true
        action_button.hide()
        drop_button.hide()
        restart_button.show()
        preview.player.locked = true
        preview.touch.cancel()
        var result := simulation.result(preview.routes)
        preview.set_meta("scramble_result",result)
        var text := "SCRAMBLE COMPLETE · Secured cargo\n"
        for tribe: Dictionary in preview.configuration.tribes:
            text += "%s: %d   " % [tribe.name,result.secured[tribe.id].size()]
        preview.subtitle.text = text + "\nUnsecured: %d · Preview only; ocean recovery comes next." % result.unsecured.size()
    update_visuals(delta)
    update_hud()

func decide(id: int) -> void:
    if simulation.pending.has(id):
        return
    var held := simulation.carried(id)
    var actor: Node3D = preview.cast[id]
    var agent: NavigationAgent3D = agents[id]
    if not held.is_empty():
        var station: Vector3 = simulation.stations[simulation.actors[id].tribe]
        agent.target_position = station
        targets[id] = held
        if simulation.valid(id,"load",held):
            simulation.request(id,"load",held)
        return
    if targets.has(id):
        var target: String = targets[id]
        if simulation.valid(id,"pickup",target):
            simulation.request(id,"pickup",target,accessible(id,"pickup",target))
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
    else:
        var destination: Vector3 = simulation.items[best].position
        var path := NavigationServer3D.map_get_path(agent.get_navigation_map(),actor.position,destination,true)
        if path.is_empty() or path[path.size()-1].distance_to(destination) > 1.2:
            rejected[str(id) + ":" + best] = simulation.elapsed + 8
            targets.erase(id)
            return
        targets[id] = best
        agent.target_position = destination

func update_visuals(delta: float) -> void:
    var counts := {}
    for id: String in simulation.items:
        var item: Dictionary = simulation.items[id]
        var visual: Node3D = visuals[id]
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
            var actor: CampHumanoidMotor = preview.cast[item.actor]
            visual.position = actor.position + Vector3(0,.95,.48).rotated(Vector3.UP,actor.travel_heading)
        elif item.state == MarooningScramble.State.SECURED:
            var tribe: String = item.tribe
            var index := int(counts.get(tribe,0))
            counts[tribe] = index + 1
            var raft_index := 0
            for i in preview.configuration.tribes.size():
                if preview.configuration.tribes[i].id == tribe:
                    raft_index = i
            visual.position = preview.layout.raft_mounts[raft_index] + Vector3((index%4 - 1.5)*.65,.4 + (index/20)*.5,(index/4%5 - 2)*.7)
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
    nearest = ""
    contextual = ""
    if held.is_empty():
        var distance := 1.35
        for item: Dictionary in simulation.items.values():
            var current: float = preview.player.position.distance_to(item.position)
            if item.state in [MarooningScramble.State.ABOARD,MarooningScramble.State.DROPPED] and current < distance and accessible(id,"pickup",item.id):
                nearest = item.id
                distance = current
        if not nearest.is_empty():
            contextual = "pickup"
    else:
        nearest = held
        if simulation.valid(id,"load",held):
            contextual = "load"
        elif simulation.valid(id,"throw",held):
            contextual = "throw"
    action_button.visible = not contextual.is_empty()
    action_button.text = {"pickup":"Pick Up", "load":"Load Raft", "throw":"Throw Overboard"}.get(contextual,"")
    action_button.disabled = simulation.pending.has(id)
    drop_button.visible = not held.is_empty()

func interact() -> void:
    if not nearest.is_empty() and not contextual.is_empty():
        simulation.request(int(preview.configuration.selected),contextual,nearest,accessible(int(preview.configuration.selected),contextual,nearest))
func drop() -> void:
    var id := int(preview.configuration.selected)
    simulation.request(id,"drop",simulation.carried(id))
