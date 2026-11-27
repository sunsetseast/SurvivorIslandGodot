class_name MarooningScrambleAdapter
extends Node
var preview: MarooningPreview
var simulation := MarooningScramble.new()
var visuals: Dictionary = {}
var targets: Dictionary = {}
var agents: Dictionary = {}
var brain_elapsed := 0.0
var brain_index := 0
var stalled: Dictionary = {}
var last_positions: Dictionary = {}
var rejected: Dictionary = {}
var traffic := MarooningDeckTraffic.new()
var station_visuals: Dictionary = {}
var cargo_slots: Dictionary = {}
var carry_attachments: Dictionary = {}

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
    preview.session.configure(preview.configuration,roster,preview.layout.supply_anchors(),stations,preview.layout.deck_accesses,preview.routes,preview.layout.reward)
    simulation=preview.session.scramble
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
    set_physics_process(false)

func start() -> void:
    if preview.introducing: return
    preview.session.start()

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

func decide(id: int) -> void:
    if simulation.pending.has(id) or not simulation.eligible(id):
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
        if item.state==MarooningScramble.State.SECURED: continue
        if item.state!=MarooningScramble.State.CARRIED and visual.get_parent()!=preview:
            visual.reparent(preview,true)
            visual.rotation=Vector3(0,visual.global_rotation.y,0)
            visual.scale=Vector3.ONE
        if item.state == MarooningScramble.State.CARRIED:
            attach_carried(visual,item)
        elif item.state == MarooningScramble.State.SECURED:
            continue
        else:
            visual.position = item.position

func drop() -> void:
    var id := int(preview.configuration.selected)
    simulation.request(id,"drop",simulation.carried(id))

func review_state() -> Dictionary:
    var rows: Array = []
    for item: Dictionary in simulation.items.values():
        var point: Vector3 = simulation.actors[item.actor].position if item.state == MarooningScramble.State.CARRIED else item.position
        rows.append({"id":item.id,"type":item.type,"state":item.state,"actor":item.actor,"position":[point.x,point.y,point.z]})
    var id := int(preview.configuration.selected)
    var station: Vector3 = simulation.stations[simulation.actors[id].tribe]
    return {"items":rows,"carried":simulation.carried(id),"target":preview.hud.nearest if is_instance_valid(preview.hud) else "","action":preview.hud.command if is_instance_valid(preview.hud) else "","basket":[station.x,station.y,station.z],"pending":simulation.pending.get(id,{}),"contributions":simulation.contributions[id]}

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
