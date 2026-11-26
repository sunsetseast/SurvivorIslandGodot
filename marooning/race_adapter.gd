class_name MarooningRaceAdapter
extends Node
var preview: MarooningPreview
var simulation := MarooningRace.new()
var vessels: Dictionary = {}
var reward_visual: MarooningSupplyVisual
var started := false
var panel: VBoxContainer
var hud: Label
var legend: Label
var meter: MarooningTimingMeter
var paddle: Button
var board: Button
var jump: Button
var rest: Button
var claim_button: Button
var deck_time: Dictionary = {}
var departure_stage: Dictionary = {}
var last_position: Dictionary = {}

func _ready() -> void:
    var cargo := preview.scramble.simulation.result(preview.routes)
    simulation.configure(preview.configuration,preview.scramble.simulation.actors,cargo,preview.routes,preview.layout.reward)
    simulation.reward.id = preview.layout.reward_id
    for tribe: Dictionary in preview.configuration.tribes:
        var raft: MarooningRaft = preload("res://marooning/raft.tscn").instantiate()
        raft.name = tribe.id
        raft.build(tribe.members,Color(tribe.color))
        preview.add_child(raft)
        raft.position = preview.routes[tribe.id].raft_mount
        vessels[tribe.id] = raft
    # Race geometry exists throughout collection; movement starts only at expiry.
    set_physics_process(false)
    reward_visual = MarooningSupplyVisual.new()
    reward_visual.build("fishing")
    preview.add_child(reward_visual)
    reward_visual.hide()
    var layer := CanvasLayer.new()
    add_child(layer)
    panel = VBoxContainer.new()
    panel.theme = IslandTheme.create()
    panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
    panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    panel.offset_left = -260
    panel.offset_top = -250
    panel.offset_right = -15
    panel.offset_bottom = -12
    layer.add_child(panel)
    hud = Label.new()
    hud.add_theme_color_override("font_outline_color",Color.BLACK)
    hud.add_theme_constant_override("outline_size",5)
    panel.add_child(hud)
    legend = Label.new()
    legend.text = "Good [  PERFECT  ] Good"
    panel.add_child(legend)
    meter = MarooningTimingMeter.new()
    meter.simulation = simulation
    meter.custom_minimum_size = Vector2(220,28)
    panel.add_child(meter)
    paddle = button("Paddle",func() -> void: simulation.stroke(selected()))
    paddle.custom_minimum_size.y = 80
    board = button("Board Raft · climb",func() -> void: simulation.request_board(selected(),access(selected(),"board")))
    rest = button("Stop Paddling",toggle_rest)
    jump = button("Jump Off",jump_off)
    claim_button = button("Claim Fishing Reward",func() -> void: simulation.claim(selected(),access(selected(),"claim")))
    panel.hide()

func selected() -> int:
    return int(preview.configuration.selected)
func button(text: String, callback: Callable) -> Button:
    var control := Button.new()
    control.text = text
    control.custom_minimum_size.y = 64
    control.pressed.connect(callback)
    panel.add_child(control)
    return control
func begin() -> void:
    if started:
        return
    started = true
    var cargo := preview.scramble.simulation.result(preview.routes)
    simulation = MarooningRace.new()
    simulation.configure(preview.configuration,preview.scramble.simulation.actors,cargo,preview.routes,preview.layout.reward)
    simulation.reward.id = preview.layout.reward_id
    simulation.timing_scale = clampf(float(preview.preferences.get("paddle_timing_scale",1.0)),.7,1.8)
    meter.simulation = simulation
    for id: int in preview.cast:
        var actor: CampPhysicalMotor = preview.cast[id]
        actor.water = CampWaterSurface.new(0,preview.layout.bed)
        actor.movement_speed_multiplier = 1
        deck_time[id] = 0.0
        departure_stage[id] = 0
    preview.player.locked = false
    preview.touch.cancel()
    panel.show()
    set_physics_process(true)
    preview.subtitle.text = "ABANDON SHIP · 18 seconds to board\nUse the bow ramp. Reach your raft’s stern to climb aboard, or swim."
func toggle_rest() -> void:
    var actor: Dictionary = simulation.actors[selected()]
    actor.paddling = not actor.paddling
    if not actor.paddling:
        actor.power = 0.0
func jump_off() -> void:
    if simulation.leave(selected()):
        var actor: CampPhysicalMotor = preview.player
        actor.raft_attached = false
        actor.position = simulation.actors[selected()].position
        actor.velocity = Vector3.ZERO
        actor.planar = Vector3.ZERO
        preview.touch.cancel()
func access(id: int, action: String) -> bool:
    var actor: CampPhysicalMotor = preview.cast[id]
    var target := simulation.boarding_point(simulation.actors[id].tribe) if action == "board" else preview.layout.reward
    var query := PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.8,target+Vector3.UP*(.8 if action == "board" else 2.0),1)
    return preview.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func _physics_process(delta: float) -> void:
    simulation.suspended = preview.scramble.simulation.suspended
    if simulation.suspended:
        return
    for id: int in preview.cast:
        var actor: CampPhysicalMotor = preview.cast[id]
        var state: Dictionary = simulation.actors[id]
        if state.raft.is_empty():
            state.position = actor.position
            if actor.swimming():
                state.mode = "swimming"
                if last_position.has(id):
                    state.swim_distance += actor.position.distance_to(last_position[id])
                actor.movement_speed_multiplier = simulation.swim_speed(id) / CampPhysicalMotor.SWIM_SPEED
            else:
                actor.movement_speed_multiplier = 1
            if id != selected():
                var before_move: Vector3 = actor.position
                move_npc(id,delta)
                if actor.swimming():
                    state.swim_distance += before_move.distance_to(actor.position)
        last_position[id] = actor.position
    simulation.advance(delta,access)
    for tribe: String in vessels:
        vessels[tribe].present(simulation.rafts[tribe],simulation.actors,simulation.elapsed,delta)
    for id: int in preview.cast:
        var state: Dictionary = simulation.actors[id]
        var actor: CampPhysicalMotor = preview.cast[id]
        actor.raft_attached = not state.raft.is_empty()
        if actor.raft_attached:
            actor.position = vessels[state.tribe].to_global(MarooningRace.seat(int(state.seat_index)))
            actor.set_heading(simulation.rafts[state.tribe].heading)
        elif state.mode == "swimming" and actor.position.distance_to(state.position) > 2.0:
            # A single validated jump transition, not per-frame swimmer attachment.
            actor.position = state.position
        if simulation.rafts[state.tribe].arrived and actor.raft_attached:
            # A real near-raft release; motors then swim/wade/walk to the beach.
            simulation.leave(id)
            actor.position = state.position
            actor.raft_attached = false
    for raft: Dictionary in simulation.rafts.values():
        simulation.update_mass(raft)
    attach_cargo()
    update_hud()
    if not simulation.reward.tribe.is_empty():
        var package := preview.bay.get_node_or_null("IllustrativeFishingPackage")
        if package != null:
            package.hide()
        reward_visual.show()
        var reward: Dictionary = simulation.reward
        if int(reward.carrier) != 0:
            reward_visual.position = preview.cast[int(reward.carrier)].position + Vector3(0,.8,.4)
        elif reward.location == "raft":
            reward_visual.position = vessels[reward.tribe].to_global(Vector3(0,.4,3.1))
        else:
            reward_visual.position = simulation.rafts[reward.tribe].destination + Vector3.UP*.2
    if simulation.phase == MarooningRace.Phase.ARRIVAL_COMPLETE:
        finish()
func move_npc(id: int, delta: float) -> void:
    var actor: CampHumanoidMotor = preview.cast[id]
    var state: Dictionary = simulation.actors[id]
    if state.mode == "arrived":
        return
    var goal := simulation.actor_objective(id)
    if actor.position.y > .4 and actor.position.z < 18:
        deck_time[id] = float(deck_time[id]) + delta
        var stage := int(departure_stage[id])
        if stage == 0:
            var agent: NavigationAgent3D = preview.scramble.agents[id]
            agent.target_position = Vector3(0,preview.layout.deck_y,6)
            goal = agent.get_next_path_position()
            if actor.position.distance_to(Vector3(0,preview.layout.deck_y,6)) < 3:
                goal = Vector3(0,preview.layout.deck_y,6)
            if actor.position.distance_to(Vector3(0,preview.layout.deck_y,6)) < 1.2:
                departure_stage[id] = 1
        else:
            goal = Vector3(0,preview.layout.deck_y+1.3,20)
        if float(deck_time[id]) > 40:
            # Genuine deck navigation failure; bounded once, visible in journal.
            actor.position = Vector3((id%3-1)*1.0,preview.layout.deck_y+.2,6)
            state.position = actor.position
            deck_time[id] = -1000.0
            departure_stage[id] = 1
            simulation.event("navigation_recovery",id)
    elif simulation.rafts[state.tribe].arrived:
        goal = simulation.arrival_point(id)
    elif int(departure_stage[id]) < 4 and actor.position.z > 12:
        # Clear the bow before turning back along the OUTSIDE of the hull.
        if int(departure_stage[id]) < 2:
            departure_stage[id] = 2
        var side := signf(simulation.rafts[state.tribe].position.x)
        if int(departure_stage[id]) == 2:
            goal = Vector3(0,0,25)
            if actor.position.z > 24:
                departure_stage[id] = 3
        else:
            goal = Vector3(side*13,0,25)
            if absf(actor.position.x) > 12:
                departure_stage[id] = 4
    elif int(state.boardings) == 0 and int(departure_stage[id]) in [4,5]:
        var raft: Dictionary = simulation.rafts[state.tribe]
        var side := signf(raft.position.x)
        var outside_x: float = raft.position.x + side*4.5
        if int(departure_stage[id]) == 4:
            goal = Vector3(outside_x,0,25)
            if absf(actor.position.x-outside_x)<.8:
                departure_stage[id] = 5
        else:
            goal = Vector3(outside_x,0,raft.position.z-6.5)
            if actor.position.distance_to(goal)<2.0:
                departure_stage[id] = 6
    elif int(state.boardings) == 0 or simulation.phase == MarooningRace.Phase.BOARDING or state.mode != "swimming":
        goal = simulation.boarding_point(state.tribe)
    elif simulation.reward.tribe.is_empty():
        var raft: Dictionary = simulation.rafts[state.tribe]
        # Reboard when it is reachable and beats the independent swim estimate.
        if actor.position.distance_to(simulation.boarding_point(state.tribe)) < 14 and float(raft.speed) < simulation.swim_speed(id):
            goal = simulation.boarding_point(state.tribe)
    if simulation.can_board(id) and simulation.elapsed >= float(state.reconsider):
        simulation.request_board(id,access(id,"board"))
    var direction := actor.position.direction_to(goal)
    direction.y = 0
    actor.walk_direction(direction,true,delta)
    if actor.position.y <= .2:
        state.mode = "swimming"
func attach_cargo() -> void:
    var counts := {}
    for id: String in preview.scramble.simulation.items:
        var item: Dictionary = preview.scramble.simulation.items[id]
        if item.state != MarooningScramble.State.SECURED:
            continue
        var index := int(counts.get(item.tribe,0))
        counts[item.tribe] = index+1
        var visual: Node3D = preview.scramble.visuals[id]
        var vessel: MarooningRaft = vessels[item.tribe]
        visual.global_position = vessel.to_global(Vector3((index%2-.5)*.65,.3+(index/12)*.45,(index/2%6-2.5)*.65))
        visual.rotation.y = vessel.rotation.y
func update_hud() -> void:
    var actor: Dictionary = simulation.actors[selected()]
    var raft: Dictionary = simulation.rafts[actor.tribe]
    var aboard: bool = not actor.raft.is_empty()
    board.visible = not aboard and simulation.can_board(selected())
    paddle.visible = aboard and actor.paddling and simulation.phase != MarooningRace.Phase.BOARDING
    rest.visible = aboard
    rest.text = "Stop Paddling" if actor.paddling else "Begin Paddling"
    jump.visible = aboard
    claim_button.visible = simulation.reward.tribe.is_empty() and actor.position.distance_to(preview.layout.reward) < 4.5
    meter.visible = paddle.visible
    legend.visible = paddle.visible
    hud.text = "%.1f m/s · Crew %d · Sync %d%%\n%s" % [raft.speed,raft.crew.size(),float(raft.sync)*100,simulation.feedback]
    if simulation.phase == MarooningRace.Phase.BOARDING:
        hud.text = "Boarding · %ds" % ceili(simulation.boarding_seconds-simulation.elapsed)
    elif not simulation.reward.tribe.is_empty():
        preview.subtitle.text = "%s claimed the fishing equipment. Head to your tribe’s landing." % simulation.reward.tribe
func finish() -> void:
    set_physics_process(false)
    preview.touch.cancel()
    preview.player.locked = true
    preview.set_meta("marooning_result",simulation.result())
    panel.hide()
    preview.scramble.restart_button.show()
    var text := "ARRIVAL COMPLETE · Equipment secured\n"
    var totals := {}
    var own: String = simulation.actors[selected()].tribe
    for item: Dictionary in simulation.scramble_result.secured[own]:
        totals[item.type] = int(totals.get(item.type,0)) + int(preview.scramble.simulation.definitions[item.type].quantity)
    for type: String in totals:
        var definition: Dictionary = preview.scramble.simulation.definitions[type]
        text += "%s: %d %s · " % [definition.name,totals[type],definition.unit]
    var actor: Dictionary = simulation.actors[selected()]
    var supply_stats: Dictionary = simulation.scramble_result.contributions[selected()]
    text += "\nYou: %d loads · %d successful thefts · %d failed thefts" % [supply_stats.get("load_success",0),supply_stats.get("steal_success",0),supply_stats.get("steal_failed",0)]
    text += "\nFishing reward: %s · You: %d strokes (%d Perfect), %.0fm swimming" % ["won" if simulation.reward.tribe == own else "not won",actor.strokes,actor.perfect,actor.swim_distance]
    preview.subtitle.grow_vertical = Control.GROW_DIRECTION_BEGIN
    preview.subtitle.offset_top = -270
    preview.subtitle.text = text
