class_name MarooningDeckTraffic
extends RefCounted
## Deck-only physical navigation. Reservations guide traffic, never item authority.
var adapter: MarooningScrambleAdapter
var intents: Dictionary = {}
var paths: Dictionary = {}
var goals: Dictionary = {}
var slots: Dictionary = {}
var samples: Dictionary = {}
var blocked: Dictionary = {}
var safe: Dictionary = {}
var resets: Dictionary = {}
var stalled_seconds: Dictionary = {}
var immobile_seconds: Dictionary = {}
var slot_rotation: Dictionary = {}
var parking: Dictionary = {}
var yields: Dictionary = {}
var contact_obstacles: Dictionary={}
var escape_debug: Dictionary={}
var human_obstacle: NavigationObstacle3D

func bind(owner_node: MarooningScrambleAdapter) -> void:
    adapter = owner_node
    for id: int in adapter.agents: configure_agent(id)
    var obstacle := NavigationObstacle3D.new()
    human_obstacle=obstacle
    obstacle.name = "HumanAvoidance"
    obstacle.radius = .46
    obstacle.height = 1.7
    obstacle.avoidance_enabled = true
    adapter.preview.player.add_child(obstacle)

func update_player() -> void:
    if is_instance_valid(human_obstacle):
        human_obstacle.velocity = adapter.preview.player.get_real_velocity()
        human_obstacle.avoidance_enabled = adapter.simulation.actors[int(adapter.preview.configuration.selected)].place=="deck" and not adapter.agents.has(int(adapter.preview.configuration.selected))

func configure_agent(id: int) -> void:
    var agent: NavigationAgent3D = adapter.agents[id]
    agent.path_desired_distance = .05 # Planar path cursor below owns advancement.
    agent.target_desired_distance = .05
    agent.avoidance_enabled = true
    agent.radius = .43
    agent.height = 1.7
    agent.neighbor_distance = 3.0
    agent.max_neighbors = 8
    agent.time_horizon_agents = .8
    agent.max_speed = 2.3
    agent.avoidance_priority = .5 + (id%3)*.02
    agent.velocity_computed.connect(func(v: Vector3) -> void: safe[id] = v)
    var actor: CampHumanoidMotor = adapter.preview.cast[id]
    actor.collision_mask = 1 | 2 | 4 | 8
    if id == int(adapter.preview.configuration.selected):
        var human_obstacle := actor.get_node_or_null("HumanAvoidance")
        if human_obstacle != null: human_obstacle.avoidance_enabled = false

static func planar(a: Vector3,b: Vector3) -> float:
    return Vector2(a.x-b.x,a.z-b.z).length()

func intent(id: int) -> String:
    var sim := adapter.simulation
    if sim.pending.has(id):
        return "depositing" if sim.pending[id].action=="load" else "interacting"
    if not sim.carried(id).is_empty() and not slots.has(id): return "choosing unloading position"
    return str(intents.get(id,"selecting supply"))

func release(id: int) -> void:
    slots.erase(id)

func unloading_goal(id: int) -> Vector3:
    var sim := adapter.simulation
    var tribe: String = sim.actors[id].tribe
    var available: Array = sim.unloading[tribe]
    if slots.has(id):
        return available[int(slots[id])]
    var best := -1
    var distance := INF
    for offset in available.size():
        var index := (offset+int(slot_rotation.get(id,0)))%available.size()
        var occupied := false
        for other: int in slots:
            if other != id and sim.actors[other].tribe == tribe and slots[other] == index: occupied = true
        var score := offset*.35 + planar(adapter.preview.cast[id].position,available[index])*.05
        if not occupied and score < distance:
            best = index
            distance = score
    if best < 0:
        intents[id] = "queue"
        return parking_goal(id)
    slots[id] = best
    return available[best]

func parking_goal(id: int) -> Vector3:
    if parking.has(id): return parking[id]
    var actor: Node3D = adapter.preview.cast[id]
    var map: RID = adapter.agents[id].get_navigation_map()
    var best: Vector3 = actor.position
    var distance := INF
    for z: float in [-1.8,-.6,.6,1.8,3.0,4.2,5.4,6.6,7.8]:
        for x: float in [-2.7,-1.8,-.9,0.0,.9,1.8,2.7]:
            var point := Vector3(x,adapter.preview.layout.deck_y,z)
            var clear := true
            for other: Vector3 in parking.values():
                if planar(point,other)<.95: clear = false
            for station: Vector3 in adapter.simulation.stations.values():
                if planar(point,station)<1.8: clear = false
            for other_id: int in adapter.preview.cast:
                if other_id != id and planar(point,adapter.preview.cast[other_id].position)<.95: clear = false
            var closest := NavigationServer3D.map_get_closest_point(map,point)
            if planar(closest,point)>.2 or closest.y-point.y>.35: clear = false
            var score := planar(point,actor.position)
            if clear and score<distance:
                best = point
                distance = score
    parking[id] = best
    return best

func target(id: int, point: Vector3, intent: String) -> void:
    intents[id] = intent
    if goals.has(id) and planar(goals[id],point) < .15:
        return
    goals[id] = point
    replan(id)

func replan(id: int) -> void:
    var actor: Node3D = adapter.preview.cast[id]
    var agent: NavigationAgent3D = adapter.agents[id]
    agent.target_position = goals[id]
    paths[id] = NavigationServer3D.map_get_path(agent.get_navigation_map(),actor.position,goals[id],true)
    resets[id] = int(resets.get(id,0)) + 1

func step(id: int, delta: float) -> void:
    var actor: CampHumanoidMotor = adapter.preview.cast[id]
    var sim := adapter.simulation
    var clock := sim.elapsed
    var desired := Vector3.ZERO
    var waiting := sim.pending.has(id) or not goals.has(id)
    if not waiting:
        var path: PackedVector3Array = paths.get(id,PackedVector3Array())
        while not path.is_empty() and planar(actor.position,path[0]) < .15:
            path.remove_at(0)
        paths[id] = path
        var goal: Vector3 = goals[id]
        var point: Vector3 = path[0] if not path.is_empty() else goal
        var distance := planar(actor.position,goal)
        if distance > .2:
            desired = Vector3(point.x-actor.position.x,0,point.z-actor.position.z).normalized() * minf(1.0,distance/.65)
        else:
            # Reaching an approach is not delivery: a body may still be on the
            # wrong elevation or behind collision. Keep sampling that carrier's
            # progress until the ordinary validated deposit actually starts.
            waiting = sim.carried(id).is_empty()
    actor.movement_speed_multiplier = sim.multiplier(id) * (.88+sim.rating(id,"speed")*.018)
    if yields.has(id):
        var retreat: Dictionary = yields[id]
        if clock<float(retreat.until) and planar(actor.position,retreat.point)>.2:
            desired = Vector3(retreat.point.x-actor.position.x,0,retreat.point.z-actor.position.z).normalized()*.7
            waiting = sim.pending.has(id)
        else:
            yields.erase(id)
            if goals.has(id): replan(id)
    var speed := CampPhysicalMotor.WALK_SPEED * actor.movement_speed_multiplier
    adapter.agents[id].get_next_path_position()
    adapter.agents[id].velocity = desired * speed
    var velocity: Vector3 = safe.get(id,Vector3.ZERO)
    if waiting:
        # RVO assumes idle neighbors also yield; discarding their safe velocity deadlocks carriers.
        velocity = Vector3.ZERO if sim.pending.has(id) else velocity.limit_length(.35)
    adapter.agents[id].avoidance_priority = 1.0 if sim.pending.has(id) else ((.98+(id%17)*.0008) if yields.has(id) else ((.70+(id%17)*.009) if slots.has(id) else (.4 if not sim.carried(id).is_empty() else .3)))
    adapter.agents[id].max_speed = 0.0 if sim.pending.has(id) else speed
    # Ignore numerical RVO noise; stationary actors retain their heading.
    if velocity.length() < .025: velocity = Vector3.ZERO
    actor.walk_direction(velocity/maxf(.1,speed),false,delta)
    # Side-to-side motion is not route progress. Measure the remaining planar
    # polyline, so wriggling against people cannot reset the stall deadline.
    var remaining := 0.0
    var cursor := actor.position
    for waypoint: Vector3 in paths.get(id,PackedVector3Array()):
        remaining += planar(cursor,waypoint)
        cursor = waypoint
    if goals.has(id): remaining += planar(cursor,goals[id])
    var goal: Vector3 = goals.get(id,actor.position)
    if not samples.has(id): samples[id] = {"at":clock,"remaining":remaining,"goal":goal,"position":actor.position}
    var sample: Dictionary = samples[id]
    if clock-float(sample.at) >= 1.0:
        var same_goal := planar(goal,sample.goal)<.15
        var carrying_still := not sim.carried(id).is_empty() and not sim.pending.has(id) and planar(actor.position,sample.position)<.10
        immobile_seconds[id]=float(immobile_seconds.get(id,0))+clock-float(sample.at) if carrying_still else 0.0
        var progressed := float(sample.remaining)-remaining >= .12
        if not waiting and same_goal and not progressed:
            blocked[id] = float(blocked.get(id,0)) + clock-float(sample.at)
            stalled_seconds[id] = float(stalled_seconds.get(id,0))+clock-float(sample.at)
        else: blocked[id] = 0.0
        samples[id] = {"at":clock,"remaining":remaining,"goal":goal,"position":actor.position}
        if float(blocked.get(id,0)) > 2.5 or float(immobile_seconds.get(id,0))>1.5:
            register_static_contacts(actor)
            # Repath first, then release the approach for an alternate/yield. Never teleport.
            replan(id)
            # A real short retreat breaks a head-on/local avoidance equilibrium.
            var heading := (goals[id] as Vector3)-actor.position
            heading.y=0
            heading=heading.normalized()
            if heading.is_zero_approx(): heading=Vector3(-signf(actor.position.x),0,0)
            var retreat := escape_point(id,heading)
            if retreat!=Vector3.INF: yields[id]={"point":retreat,"until":clock+2.5}
            parking.erase(id)
            slot_rotation[id] = (int(slots.get(id,0))+1)%3
            release(id)
            if adapter.targets.has(id):
                adapter.rejected[str(id)+":"+str(adapter.targets[id])] = sim.elapsed+8
            adapter.targets.erase(id)
            goals.erase(id)
            blocked[id] = 0.0
            intents[id] = "yielding"
            adapter.preview.session.events.append({"source":"navigation","action":"deck_repath","actor":id,"elapsed":clock,"position":actor.position,"held":sim.carried(id),"reason":"no_route_progress","physical_retreat":yields.has(id)})

func escape_point(id: int,heading: Vector3) -> Vector3:
    var actor: CampPhysicalMotor=adapter.preview.cast[id]
    var rejected := {"short_motion":0,"bounds":0,"floor":0,"occupied":0,"accepted":0}
    escape_debug[id]=rejected
    var shape := CapsuleShape3D.new()
    shape.radius=CampPhysicalMotor.RADIUS
    shape.height=1.69
    var directions: Array[Vector3]=[-heading,Vector3(heading.z,0,-heading.x),Vector3(-heading.z,0,heading.x)]
    for index in 8: directions.append(Vector3(sin(index*TAU/8),0,cos(index*TAU/8)))
    for direction in directions:
        var motion := direction*.95
        var collision := KinematicCollision3D.new()
        if actor.test_move(actor.global_transform,motion,collision):
            if collision.get_travel().length()<.25:
                rejected.short_motion+=1
                continue
            motion=collision.get_travel()*.9
        var candidate := actor.position+motion
        # A short physical retreat may step outside a simplified nav polygon,
        # but must stay on real, level deck and keep the full capsule clear.
        if absf(candidate.x)>3.55 or candidate.z< -5.8 or candidate.z>8.7:
            rejected.bounds+=1
            continue
        var down := PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*.7,candidate-Vector3.UP*.4,1)
        var floor_hit := adapter.preview.get_world_3d().direct_space_state.intersect_ray(down)
        if floor_hit.is_empty() or floor_hit.normal.y<.75 or absf(floor_hit.position.y-actor.position.y)>.15:
            rejected.floor+=1
            continue
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape=shape
        query.transform.origin=Vector3(candidate.x,floor_hit.position.y+.025+.845,candidate.z)
        query.collision_mask=1|2|4
        query.exclude=[actor.get_rid()]
        if not adapter.preview.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
            rejected.occupied+=1
            continue
        rejected.accepted+=1
        return candidate
    return Vector3.INF

func register_static_contacts(actor: CampPhysicalMotor) -> void:
    # RVO does not infer static obstacles from the navigation mesh. A blocked
    # safe velocity must teach avoidance about the actual wall, not keep pushing it.
    for index in actor.get_slide_collision_count():
        var hit := actor.get_slide_collision(index)
        var collider := hit.get_collider()
        var normal := hit.get_normal()
        if not collider is StaticBody3D or absf(normal.y)>.45: continue
        var point := hit.get_position()-normal*.08
        var key := Vector2i(roundi(point.x/.35),roundi(point.z/.35))
        if contact_obstacles.has(key) or contact_obstacles.size()>=48: continue
        var obstacle := NavigationObstacle3D.new()
        obstacle.name="MeasuredStaticAvoidance"
        obstacle.radius=.12
        obstacle.height=1.8
        obstacle.position=Vector3(point.x,actor.position.y,point.z)
        obstacle.avoidance_enabled=true
        adapter.preview.add_child(obstacle)
        contact_obstacles[key]=obstacle
