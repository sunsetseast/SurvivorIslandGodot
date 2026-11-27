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
var slot_rotation: Dictionary = {}
var parking: Dictionary = {}
var yields: Dictionary = {}
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
    if is_instance_valid(human_obstacle): human_obstacle.velocity = adapter.preview.player.get_real_velocity()

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
        return sim.stations[tribe] + Vector3(-signf(sim.stations[tribe].x)*(2.0+(id%2)*.85),0,2.2+(id%3)*.95)
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
    var clock := sim.elapsed + (adapter.preview.race.simulation.elapsed if adapter.preview.race.started else 0.0)
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
    actor.movement_speed_multiplier = (sim.multiplier(id) if not adapter.preview.race.started else 1.0) * (.88+sim.rating(id,"speed")*.018)
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
    adapter.agents[id].avoidance_priority = (.70+(id%17)*.009) if slots.has(id) else (.4 if not sim.carried(id).is_empty() else .3)
    # Ignore numerical RVO noise; stationary actors retain their heading.
    if velocity.length() < .12: velocity = Vector3.ZERO
    actor.walk_direction(velocity/maxf(.1,speed),false,delta)
    if not samples.has(id): samples[id] = {"at":clock,"position":actor.position}
    var sample: Dictionary = samples[id]
    if clock-float(sample.at) >= 1.0:
        var moved := planar(actor.position,sample.position)
        if not waiting and moved < .18:
            blocked[id] = float(blocked.get(id,0)) + clock-float(sample.at)
            stalled_seconds[id] = float(stalled_seconds.get(id,0))+clock-float(sample.at)
        else: blocked[id] = 0.0
        samples[id] = {"at":clock,"position":actor.position}
        if float(blocked.get(id,0)) > 2.5:
            # Repath first, then release the approach for an alternate/yield. Never teleport.
            replan(id)
            # A real short retreat breaks a head-on/local avoidance equilibrium.
            var heading := (goals[id] as Vector3)-actor.position
            heading.y=0
            heading=heading.normalized()
            for offset: Vector3 in [Vector3(heading.z,0,-heading.x),Vector3(-heading.z,0,heading.x),-heading]:
                var candidate := actor.position+offset*.95
                var closest := NavigationServer3D.map_get_closest_point(adapter.agents[id].get_navigation_map(),candidate)
                if planar(closest,candidate)>.2 or absf(closest.y-actor.position.y)>.4: continue
                var clear := true
                for other_id: int in adapter.preview.cast:
                    if other_id!=id and planar(candidate,adapter.preview.cast[other_id].position)<.85: clear=false
                var ray := PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.8,candidate+Vector3.UP*.8,1)
                if not adapter.preview.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): clear=false
                if clear:
                    yields[id] = {"point":candidate,"until":clock+2.5}
                    break
            parking.erase(id)
            slot_rotation[id] = (int(slots.get(id,0))+1)%3
            release(id)
            if adapter.targets.has(id):
                adapter.rejected[str(id)+":"+str(adapter.targets[id])] = sim.elapsed+8
            adapter.targets.erase(id)
            goals.erase(id)
            blocked[id] = 0.0
            intents[id] = "yielding"
