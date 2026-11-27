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
var cargo_origins: Dictionary = {}
var bow_owner := 0
var shore_clear: Dictionary = {}

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
    paddle.custom_minimum_size.y = 90
    board = button("Board Raft",func() -> void: simulation.request_board(selected(),access(selected(),"board")))
    rest = button("Stop Paddling",toggle_rest)
    jump = button("Jump Off",jump_off)
    claim_button = button("Claim Fishing Reward",func() -> void: simulation.claim(selected(),access(selected(),"claim")))
    panel.hide()

func selected() -> int:
    return int(preview.configuration.selected)
func button(text: String, callback: Callable) -> Button:
    var control := Button.new()
    control.text = text
    control.custom_minimum_size.y = 90
    control.add_theme_font_size_override("font_size",26)
    control.pressed.connect(callback)
    panel.add_child(control)
    return control
func begin() -> void:
    if started:
        return
    started = true
    preview.scramble.traffic.slots.clear()
    preview.scramble.traffic.yields.clear()
    preview.scramble.traffic.parking.clear()
    var cargo := preview.scramble.simulation.result(preview.routes)
    simulation = MarooningRace.new()
    simulation.configure(preview.configuration,preview.scramble.simulation.actors,cargo,preview.routes,preview.layout.reward)
    simulation.reward.id = preview.layout.reward_id
    simulation.timing_scale = clampf(float(preview.preferences.get("paddle_timing_scale",1.0)),.7,1.8)
    meter.simulation = simulation
    for item_id: String in preview.scramble.visuals:
        cargo_origins[item_id] = preview.scramble.visuals[item_id].position
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
    preview.subtitle.text = "ASSEMBLE · up to 60 seconds to board\nFollow the central bow exit. Board your colored raft at its stern, or deliberately swim."
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
    var target := simulation.boarding_access(id) if action == "board" else preview.layout.reward
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
        var was_attached := actor.raft_attached
        actor.raft_attached = not state.raft.is_empty()
        if was_attached and not actor.raft_attached:
            actor.position = state.position
            actor.velocity = Vector3.ZERO
            actor.planar = Vector3.ZERO
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
            actor.velocity = Vector3.ZERO
            actor.planar = Vector3.ZERO
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
        if bow_owner != 0 and (not preview.cast.has(bow_owner) or preview.cast[bow_owner].position.z>9.8 or preview.cast[bow_owner].position.y<.3):
            bow_owner = 0
        if bow_owner == 0:
            var nearest_distance := INF
            for candidate: int in preview.scramble.agents:
                var body: Node3D = preview.cast[candidate]
                if int(departure_stage.get(candidate,0)) == 0 and body.position.y>.4 and body.position.z<13:
                    var distance := MarooningDeckTraffic.planar(body.position,Vector3(0,preview.layout.deck_y,7.5))
                    if distance<nearest_distance:
                        nearest_distance = distance
                        bow_owner = candidate
        if stage == 0:
            var traffic := preview.scramble.traffic
            var centre := Vector3(0,preview.layout.deck_y,7.5)
            if bow_owner != id:
                var rank: int = preview.cast.keys().find(id)
                centre = Vector3(-1.65 if rank%2==0 else 1.65,preview.layout.deck_y,7.0-(rank/2)*.90)
            traffic.target(id,centre,"departing")
            traffic.step(id,delta)
            if bow_owner == id and absf(actor.position.x)<.22 and MarooningDeckTraffic.planar(actor.position,centre)<.3:
                departure_stage[id] = 1
                preview.scramble.agents[id].avoidance_enabled = false
            return
        else:
            # Single-file bow access: local RVO must not push a capsule outside the narrow opening.
            goal = Vector3(0,preview.layout.deck_y,20)
    elif simulation.rafts[state.tribe].arrived:
        goal = simulation.arrival_point(id)
        var raft: Dictionary = simulation.rafts[state.tribe]
        var local := (actor.position-(raft.position as Vector3)).rotated(Vector3.UP,-float(raft.heading))
        if local.z>=6.7: shore_clear[id] = true
        if not shore_clear.has(id):
            var side := -1.0 if local.x<0 else 1.0
            var point := Vector3(side*4.5,0,local.z if absf(local.x)<4 else 7.0)
            goal = (raft.position as Vector3)+point.rotated(Vector3.UP,float(raft.heading))
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
    if preview.scramble.agents.has(id): preview.scramble.agents[id].avoidance_enabled = false
    var direction := goal-actor.position
    direction.y = 0
    direction = direction.normalized()*minf(1.0,direction.length()/.6)
    # Physical passing near swimmers and landed actors; arrived humans keep control/position.
    var forward := direction.normalized()
    for other_id: int in preview.cast:
        if other_id == id or not simulation.actors[other_id].raft.is_empty(): continue
        var other: Node3D = preview.cast[other_id]
        if absf(actor.position.y-other.position.y)>1.7: continue
        var offset := Vector3(actor.position.x-other.position.x,0,actor.position.z-other.position.z)
        var distance := offset.length()
        if distance<1.05 and distance>.01:
            direction += offset.normalized()*maxf(0,1.05-distance)*1.8
            if forward.dot(-offset.normalized())>.6:
                direction += Vector3(forward.z,0,-forward.x)*.8
    direction = direction.limit_length()
    actor.walk_direction(direction,false if actor.position.z<18 and actor.position.y>.3 else true,delta)
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
        var slot := vessel.to_global(Vector3((index%2-.5)*.65,.3+(index/12)*.45,(index/2%6-2.5)*.65))
        visual.global_position = (cargo_origins.get(id,slot) as Vector3).lerp(slot,clampf(simulation.elapsed/.85,0,1))
        visual.scale = Vector3.ONE*.65
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
    if claim_button.visible:
        board.hide()
        paddle.hide()
    meter.visible = paddle.visible
    legend.visible = paddle.visible
    hud.text = "%.1f m/s · Crew %d · Sync %d%%\n%s" % [raft.speed,raft.crew.size(),float(raft.sync)*100,simulation.feedback]
    if simulation.phase == MarooningRace.Phase.BOARDING:
        hud.text = "Assemble · %ds maximum\nOwn raft: %dm · follow bow exit" % [ceili(simulation.boarding_seconds-simulation.elapsed),ceili(actor.position.distance_to(simulation.boarding_point(actor.tribe)))]
    elif not simulation.reward.tribe.is_empty():
        var winner_name: String = simulation.reward.tribe
        for tribe: Dictionary in preview.configuration.tribes:
            if tribe.id == simulation.reward.tribe:
                winner_name = tribe.name
        preview.subtitle.text = "%s claimed the fishing equipment.\nHead to your tribe’s landing." % winner_name
    else:
        preview.subtitle.text = "Paddle together · your tribe steers automatically." if aboard else "Swim for the fishing equipment, or board your raft at a colored side or stern point."
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

func layout_actions(area: Rect2) -> void:
    var size := preview.get_viewport().get_visible_rect().size
    var right := maxf(18,size.x-area.end.x+18)
    var bottom := maxf(12,size.y-area.end.y+12)
    panel.offset_left=-right-245
    panel.offset_right=-right
    panel.offset_bottom=-bottom
