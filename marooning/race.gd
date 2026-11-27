class_name MarooningRace
extends RefCounted
## Travel authority. A raft's state, never a race-wide boarding phase, gates force.
enum Phase { BOARDING, RAFT_RACE, CAMP_APPROACH, ARRIVAL_COMPLETE }
const STEP := 1.0/60.0
const BEAT := 1.6
const PERSON_KG := 75.0
const STROKE_SECONDS := .65
const BOARD_RANGE := 2.7
var phase := Phase.BOARDING
var active := true
var elapsed := 0.0
var accumulator := 0.0
var suspended := false
var configuration: Dictionary
var scramble_result: Dictionary
var actors: Dictionary = {}
var rafts: Dictionary = {}
var pending: Dictionary = {}
var events: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var reward := {"id":"fishing-equipment-preview","status":"available","tribe":"","actor":0,"time":0.0,"method":"","mass_kg":8.0,"carrier":0,"secured":false,"location":"platform"}
var reward_position := Vector3.ZERO
var reward_deadline := 150.0
var timing_scale := 1.0
var _beat := -1
var feedback := ""
# Retained as read-only compatibility tuning for old pure-command fixtures.
var boarding_seconds := 60.0
var assembly_minimum := 0.0

func configure(config: Dictionary, roster: Dictionary, cargo: Dictionary, routes: Dictionary, reward_point: Vector3, shared_actors := false) -> void:
    configuration=config.duplicate(true)
    scramble_result=cargo.duplicate(true)
    rng.seed=int(config.seed)
    reward_position=reward_point
    actors=roster if shared_actors else roster.duplicate(true)
    for id: int in actors:
        actors[id].merge({"raft":"","place":"deck","mode":"walking","objective":"collect","arrived":false,"recovered":false,"fatigue":0.0,"paddling":true,"power":0.0,"beat":-1,"strokes":0,"perfect":0,"good":0,"missed":0,"swim_distance":0.0,"boardings":0,"departures":0,"force_total":0.0,"impulse_total_ns":0.0,"impulse_delivered_ns":0.0,"impulse_cancelled_ns":0.0,"live_strokes":[],"stroke_at":-10.0,"stroke_phase":.5,"reconsider":0.0,"velocity":Vector3.ZERO,"cargo_batch":[],"unloaded_count":0})
    for tribe: Dictionary in config.tribes:
        for index in tribe.members.size(): actors[int(tribe.members[index])]["seat_index"]=index
        var route: Dictionary=routes[tribe.id]
        var mass := 0.0
        var cargo_ids: Array=[]
        for item: Dictionary in cargo.secured.get(tribe.id,[]):
            mass+=float(MarooningSupplyCatalog.definitions()[item.type].mass_kg)
            cargo_ids.append(item.id)
        var destination: Vector3=route.destination
        var shore: Vector3=route.get("shore_center",destination)
        var stop: Vector3=route.get("stop_position",destination-Vector3(0,0,8))
        rafts[tribe.id]={"id":route.raft_id,"state":"moored","position":route.raft_mount,"heading":float(route.get("heading",0)),"speed":0.0,"momentum":0.0,"velocity":Vector3.ZERO,"crew":[],"capacity":tribe.members.size(),"cargo_ids":cargo_ids,"cargo_kg":mass,"cargo_location":"raft","delivered_ids":{},"mass_kg":180.0+mass,"draft":0.0,"sync":0.0,"distance":0.0,"stop_position":stop,"destination":destination,"shore_center":shore,"shore_min_y":float(route.get("shore_min_y",-.05)),"destination_id":route.route_id,"arrived":false,"arrival_time":-1.0,"launch_time":-1.0,"launch_reason":"","decision_at":-1.0,"strategy_at":0.0,"max_speed":0.0,"peak_mass_kg":180.0+mass,"paddler_seconds":0.0,"crew_seconds":0.0,"waypoints":route.get("clearance",[]).duplicate(),"blocked_seconds":0.0,"repaths":0}
        rafts[tribe.id]["dock_side"]=-1.0 if route.raft_mount.x<reward_point.x else 1.0
        update_mass(rafts[tribe.id])

static func seat(index: int) -> Vector3:
    return Vector3(-1.23 if index%2==0 else 1.23,.08,-3.0+(index/2)*1.50)

func rating(id: int, key: String) -> float:
    return clampf(float(actors[id].attributes.get(key,5)),1,10)

static func access_points() -> Array[Vector3]:
    return [Vector3(0,.12,-4.12),Vector3(-2.16,.12,-2.25),Vector3(2.16,.12,-2.25),Vector3(-2.16,.12,2.25),Vector3(2.16,.12,2.25)]

func to_world(tribe: String, local: Vector3) -> Vector3:
    var raft: Dictionary=rafts[tribe]
    return raft.position+local.rotated(Vector3.UP,float(raft.heading))-Vector3.UP*float(raft.draft)

func to_local(tribe: String, point: Vector3) -> Vector3:
    var raft: Dictionary=rafts[tribe]
    return (point-raft.position+Vector3.UP*float(raft.draft)).rotated(Vector3.UP,-float(raft.heading))

func boarding_point(tribe: String) -> Vector3:
    return to_world(tribe,access_points()[0])

func nearest_access(id: int, reserve := false) -> int:
    var actor: Dictionary=actors[id]
    var best := -1
    var distance := INF
    for index in access_points().size():
        var occupied := false
        if reserve:
            for other: int in pending:
                if other!=id and pending[other].tribe==actor.tribe and int(pending[other].access)==index: occupied=true
        var gap: float=actor.position.distance_to(to_world(actor.tribe,access_points()[index]))
        if not occupied and gap<distance:
            best=index
            distance=gap
    return best

func boarding_access(id: int) -> Vector3:
    var index := int(pending[id].access) if pending.has(id) else nearest_access(id)
    return to_world(actors[id].tribe,access_points()[maxi(0,index)])

func can_board(id: int) -> bool:
    if not active or suspended or not actors.has(id): return false
    var actor: Dictionary=actors[id]
    var raft: Dictionary=rafts[actor.tribe]
    if actor.arrived or not str(actor.raft).is_empty() or pending.has(id) or raft.state not in ["moored","underway"] or raft.crew.has(id): return false
    var reserved := 0
    for climb: Dictionary in pending.values(): reserved+=int(climb.tribe==actor.tribe)
    var index := nearest_access(id,true)
    if index<0 or raft.crew.size()+reserved>=int(raft.capacity): return false
    var relative_velocity: Vector3=actor.velocity-raft.velocity
    return actor.position.distance_to(to_world(actor.tribe,access_points()[index]))<=BOARD_RANGE and relative_velocity.length()<=5.5

func request_board(id: int, accessible := true) -> bool:
    if not accessible or not can_board(id):
        feedback="Move beside your raft's colored climbing point"
        return false
    var actor: Dictionary=actors[id]
    var index := nearest_access(id,true)
    var local := to_local(actor.tribe,actor.position)
    var anchor := access_points()[index]
    var destination := seat(int(actor.seat_index))
    var walk_seconds := (absf(anchor.x)+absf(anchor.z-destination.z)+absf(destination.x))/2.8
    pending[id]={"tribe":actor.tribe,"access":index,"seat":int(actor.seat_index),"started":elapsed,"at":elapsed+.65+walk_seconds,"from_local":local,"previous_place":actor.place}
    actor.place="climbing"
    actor.mode="climbing"
    actor.power=0.0
    feedback="Climbing aboard"
    event("boarding_started",id)
    return true

func cancel_climbs(reason: String) -> void:
    for id: int in pending.keys(): cancel_climb(id,reason)

func cancel_climb(id: int, reason: String) -> void:
    if not pending.has(id): return
    var actor: Dictionary=actors[id]
    actor.place="swimming"
    actor.mode="swimming"
    pending.erase(id)
    event("boarding_cancelled_"+reason,id)

func cancel_force(id: int) -> void:
    var actor: Dictionary=actors[id]
    for stroke_row: Dictionary in actor.live_strokes:
        actor.impulse_cancelled_ns+=float(stroke_row.impulse)-float(stroke_row.delivered)
    actor.live_strokes.clear()
    actor.power=0.0

func leave(id: int) -> bool:
    if suspended or not actors.has(id): return false
    if pending.has(id):
        cancel_climb(id,"jump")
        return true
    var actor: Dictionary=actors[id]
    if actor.raft.is_empty(): return false
    var raft: Dictionary=rafts[actor.raft]
    var index := int(actor.seat_index)
    var side := -1.0 if index%2==0 else 1.0
    actor.position=to_world(actor.tribe,Vector3(side*2.85,-1.55,clampf(float(index/2)-1.0,-2,2)))
    # A voluntary jump can happen just before grounding in shallow water too.
    var bed_y: float=raft.shore_center.y+(actor.position.z-raft.shore_center.z)*.09
    actor.position.y=maxf(actor.position.y,bed_y+.04)
    raft.crew.erase(id)
    actor.raft=""
    actor.place="swimming"
    actor.mode="swimming"
    actor.objective="shore" if reward_resolved() else "reward"
    cancel_force(id)
    actor.departures+=1
    actor.reconsider=elapsed+12.0
    event("disembarked",id)
    update_mass(raft)
    return true

func set_rest(id: int, resting: bool) -> void:
    actors[id].paddling=not resting
    if resting: cancel_force(id)
    event("rest" if resting else "resume_paddling",id)

func stroke(id: int) -> String:
    if not actors.has(id): return ""
    var actor: Dictionary=actors[id]
    if not active or suspended or actor.raft.is_empty() or not actor.paddling or int(actor.beat)==int(floor(elapsed/BEAT)) or elapsed-float(actor.stroke_at)<.45:
        feedback="One stroke per cycle" if not actor.raft.is_empty() else "Board your raft to paddle"
        return ""
    if rafts[actor.tribe].state!="underway":
        feedback="Moored: encourage your crew with Let's Go"
        return ""
    var error := absf(fmod(elapsed,BEAT)/BEAT-.5)
    var grade := "Perfect" if error<=.065*timing_scale else ("Good" if error<=.17*timing_scale else "Early/Late")
    apply_stroke(id,{"Perfect":1.5,"Good":1.1,"Early/Late":.65}[grade],grade)
    feedback=grade
    return grade

func apply_stroke(id: int, quality: float, grade: String) -> void:
    var actor: Dictionary=actors[id]
    var impulse := quality*(65.0+rating(id,"strength")*9.0)*(1.0-float(actor.fatigue)*.35)*clampf(1.1-rating(id,"laziness")*.035,.75,1.1)
    actor.stroke_phase=fmod(elapsed,BEAT)/BEAT
    actor.stroke_at=elapsed
    actor.beat=int(floor(elapsed/BEAT))
    actor.strokes+=1
    actor.perfect+=int(grade=="Perfect")
    actor.good+=int(grade=="Good")
    actor.impulse_total_ns+=impulse
    actor.force_total+=impulse # v2 compatibility field: accepted impulse, in N·s.
    actor.live_strokes.append({"at":elapsed,"impulse":impulse,"delivered":0.0,"grade":grade})
    event("stroke_"+grade,id)

func integrate_strokes(id: int, from: float, until: float) -> float:
    var actor: Dictionary=actors[id]
    var delivered := 0.0
    for row: Dictionary in actor.live_strokes:
        var overlap := maxf(0,minf(until,float(row.at)+STROKE_SECONDS)-maxf(from,float(row.at)))
        var impulse := minf(float(row.impulse)-float(row.delivered),float(row.impulse)*overlap/STROKE_SECONDS)
        row.delivered+=impulse
        delivered+=impulse
    actor.live_strokes=actor.live_strokes.filter(func(row: Dictionary) -> bool: return float(row.delivered)<float(row.impulse)-.000001)
    actor.impulse_delivered_ns+=delivered
    actor.power=delivered/STEP
    return delivered

func commit_launch(tribe: String, reason: String) -> bool:
    var raft: Dictionary=rafts[tribe]
    if not active or suspended or raft.state!="moored" or raft.crew.is_empty(): return false
    var paddlers := 0
    for id_value in raft.crew: paddlers+=int(actors[int(id_value)].paddling)
    if paddlers==0: return false
    raft.state="underway"
    raft.launch_time=elapsed
    raft.launch_reason=reason
    for id_value in raft.crew:
        var id := int(id_value)
        actors[id].objective="shore" if reward_resolved() else "reward"
        schedule_stroke(id)
    event("launch_committed",int(raft.crew[0]))
    return true

func schedule_stroke(id: int) -> void:
    var actor: Dictionary=actors[id]
    var beat := int(floor(elapsed/BEAT))
    if int(actor.beat)==beat:
        actor["stroke_due"]=INF
        return
    var target := float(beat)*BEAT+BEAT*clampf(.5+rng.randf_range(-.22,.22)*(1.25-rating(id,"dexterity")*.08),.15,.85)
    actor["stroke_due"]=maxf(elapsed+STEP,minf(target,(beat+1)*BEAT-.001))
    actor["scheduled_beat"]=beat

func reward_resolved() -> bool:
    return reward.status!="available"

func claim(id: int, accessible := true) -> bool:
    if not active or suspended or not accessible or reward_resolved() or not actors.has(id): return false
    var actor: Dictionary=actors[id]
    if actor.arrived or actor.position.distance_to(reward_position)>4.5: return false
    reward.merge({"status":"claimed","tribe":actor.tribe,"actor":id,"time":elapsed,"method":"raft" if not actor.raft.is_empty() else "swim"},true)
    if not actor.raft.is_empty():
        rafts[actor.tribe].cargo_kg+=float(reward.mass_kg)
        reward.merge({"secured":true,"location":"raft"},true)
    else: reward.merge({"carrier":id,"location":"carried"},true)
    event("reward_claimed",id)
    return true

func event(action: String, id: int) -> void:
    var witnesses: Array[int]=[]
    for other: int in actors:
        if other!=id and actors[other].position.distance_to(actors[id].position)<8: witnesses.append(other)
    events.append({"source":"travel","action":action,"actor":id,"tribe":actors[id].tribe,"time":elapsed,"elapsed":elapsed,"nearby_witnesses":witnesses,"reward_id":reward.id if action=="reward_claimed" else ""})
    if events.size()>8192: events.pop_front()

func swim_speed(id: int) -> float:
    return clampf(1.5+rating(id,"endurance")*.07+rating(id,"speed")*.045+rating(id,"balance")*.015,1.8,2.8)*(1.0-float(actors[id].fatigue)*.18)*(.94 if int(reward.carrier)==id else 1.0)

func objective(tribe: String) -> Vector3:
    return rafts[tribe].shore_center if reward_resolved() else reward_position

func arrival_point(id: int) -> Vector3:
    var actor: Dictionary=actors[id]
    var index := int(actor.seat_index)
    var offset := Vector3((index%3-1)*2.5+(index/3%2)*.6,0,(index/3)*1.8-1.8+float(index%2)*.45)
    return rafts[actor.tribe].shore_center+offset

func actor_objective(id: int) -> Vector3:
    return arrival_point(id) if reward_resolved() else reward_position

func update_mass(raft: Dictionary) -> void:
    raft.mass_kg=180.0+float(raft.cargo_kg)+raft.crew.size()*PERSON_KG
    raft.peak_mass_kg=maxf(float(raft.peak_mass_kg),float(raft.mass_kg))
    raft.draft=clampf((float(raft.mass_kg)-180.0)/4000.0,0,.32)

func advance(delta: float, access: Callable = Callable()) -> void:
    if suspended or not active or phase==Phase.ARRIVAL_COMPLETE: return
    accumulator+=minf(maxf(delta,0),.25)
    while accumulator+.000001>=STEP:
        accumulator-=STEP
        step_at(elapsed+STEP,access)

func step(access: Callable) -> void:
    step_at(elapsed+STEP,access)

func step_at(game_time: float, access: Callable = Callable()) -> void:
    if suspended or not active or phase==Phase.ARRIVAL_COMPLETE: return
    var from := game_time-STEP
    elapsed=game_time
    var ids := actors.keys()
    ids.sort()
    for id: int in pending.keys():
        var climb: Dictionary=pending[id]
        var actor: Dictionary=actors[id]
        var raft: Dictionary=rafts[climb.tribe]
        if raft.state not in ["moored","underway"] or actor.arrived:
            cancel_climb(id,"vessel_state")
            continue
        var age := elapsed-float(climb.started)
        var local: Vector3
        if age<.65:
            local=(climb.from_local as Vector3).lerp(access_points()[int(climb.access)],smoothstep(0,.65,age))
        else:
            var anchor := access_points()[int(climb.access)]
            var destination := seat(int(climb.seat))
            var aisle := Vector3(0,destination.y,anchor.z)
            var row := Vector3(0,destination.y,destination.z)
            var distance := (age-.65)*2.8
            if distance<anchor.distance_to(aisle): local=anchor.move_toward(aisle,distance)
            elif distance<anchor.distance_to(aisle)+aisle.distance_to(row): local=aisle.move_toward(row,distance-anchor.distance_to(aisle))
            else: local=row.move_toward(destination,distance-anchor.distance_to(aisle)-aisle.distance_to(row))
        actor.position=to_world(actor.tribe,local)
        if elapsed+.000001<float(climb.at): continue
        if raft.crew.size()<int(raft.capacity) and not raft.crew.has(id) and (not access.is_valid() or bool(access.call(id,"climb"))):
            actor.raft=actor.tribe
            actor.place="aboard"
            actor.mode="aboard"
            actor.boardings+=1
            raft.crew.append(id)
            if int(reward.carrier)==id:
                raft.cargo_kg+=float(reward.mass_kg)
                reward.merge({"carrier":0,"secured":true,"location":"raft"},true)
                event("reward_secured",id)
            pending.erase(id)
            schedule_stroke(id)
            event("boarded",id)
        else: cancel_climb(id,"safety")
    _beat=int(floor(elapsed/BEAT))
    for id: int in ids:
        var actor: Dictionary=actors[id]
        if not actor.raft.is_empty() and rafts[actor.tribe].state=="underway":
            if int(actor.get("scheduled_beat",-1))!=_beat:
                if int(actor.beat)<_beat-1 and actor.paddling: actor.missed+=1
                schedule_stroke(id)
            if id!=int(configuration.selected) and actor.paddling and int(actor.beat)!=_beat and elapsed>=float(actor.get("stroke_due",INF)):
                stroke(id)
            integrate_strokes(id,from,elapsed)
            actor.fatigue=clampf(float(actor.fatigue)+STEP*(.0028*(1.2-rating(id,"endurance")*.07) if actor.paddling else -.008),0,1)
        elif actor.place=="swimming": actor.fatigue=clampf(float(actor.fatigue)+STEP*.002,0,1)
        else: actor.fatigue=maxf(0,float(actor.fatigue)-STEP*.008)
        if id!=int(configuration.selected) and not reward_resolved() and actor.position.distance_to(reward_position)<=4.5:
            claim(id,not access.is_valid() or bool(access.call(id,"claim")))
    if not reward_resolved() and elapsed>=reward_deadline:
        reward.status="unclaimed"
        reward.location="unclaimed"
        reward.time=elapsed
        event("reward_unclaimed",int(configuration.selected))
    for tribe: String in rafts:
        var raft: Dictionary=rafts[tribe]
        update_mass(raft)
        if raft.state=="underway": move_raft(tribe,access)
        else:
            raft.speed=0.0
            raft.momentum=0.0
            raft.velocity=Vector3.ZERO
        for id_value in raft.crew:
            var id := int(id_value)
            actors[id].position=to_world(tribe,seat(int(actors[id].seat_index)))
        if raft.state=="grounded":
            for index in raft.crew.size():
                var id := int(raft.crew[index])
                if elapsed>=float(raft.arrival_time)+.25+float(actors[id].seat_index)*.28:
                    leave(id)
                    break
        if raft.state=="underway" and elapsed>=float(raft.strategy_at):
            raft.strategy_at=elapsed+4
            strategy(tribe)
    for id: int in ids:
        var actor: Dictionary=actors[id]
        if actor.arrived:
            actor.place="shore"
            continue
        var raft: Dictionary=rafts[actor.tribe]
        var gap := Vector2(actor.position.x-raft.shore_center.x,actor.position.z-raft.shore_center.z).length()
        if actor.raft.is_empty() and not pending.has(id) and reward_resolved() and gap<=7.0 and actor.position.y>=float(raft.shore_min_y):
            actor.arrived=true
            actor.place="shore"
            actor.mode="walking"
            actor.objective="regroup"
            actor["arrival_time"]=elapsed
            for item_id: String in actor.cargo_batch: raft.delivered_ids[item_id]=true
            actor.unloaded_count+=actor.cargo_batch.size()
            actor.cargo_batch.clear()
            if int(reward.carrier)==id:
                reward.merge({"carrier":0,"secured":true,"location":"shore"},true)
                event("reward_secured",id)
            event("arrived",id)
    phase=Phase.CAMP_APPROACH if reward_resolved() else Phase.RAFT_RACE
    var own: String=actors[int(configuration.selected)].tribe
    var complete := bool(rafts[own].arrived)
    for actor: Dictionary in actors.values():
        if actor.tribe==own and not actor.arrived: complete=false
    if complete and rafts[own].delivered_ids.size()>=rafts[own].cargo_ids.size():
        rafts[own].state="regrouped"
        rafts[own].cargo_location="shore"
        phase=Phase.ARRIVAL_COMPLETE

func move_raft(tribe: String, access: Callable) -> void:
    var raft: Dictionary=rafts[tribe]
    var force := 0.0
    var direction_sum := Vector2.ZERO
    var contributors := 0
    var leadership := 0.0
    for id_value in raft.crew:
        var id := int(id_value)
        var actor: Dictionary=actors[id]
        force+=float(actor.power)
        raft.paddler_seconds+=STEP*int(actor.paddling)
        raft.crew_seconds+=STEP
        leadership=maxf(leadership,rating(id,"leader"))
        if int(actor.strokes)>0 and elapsed-float(actor.stroke_at)<=BEAT:
            direction_sum+=Vector2(cos(float(actor.stroke_phase)*TAU),sin(float(actor.stroke_phase)*TAU))
            contributors+=1
    raft.sync=direction_sum.length()/maxf(1,float(raft.crew.size()))
    var drag := 38.0*(1.0+(float(raft.mass_kg)-180.0)/1600.0)
    var acceleration := (force*(1.0+minf(.17,(.07+leadership*.01)*float(raft.sync)))-drag*float(raft.momentum)*float(raft.momentum))/float(raft.mass_kg)
    raft.momentum=clampf(float(raft.momentum)+acceleration*STEP,0,4.4)
    var target: Vector3=raft.stop_position if reward_resolved() else reward_position
    var route: Array=raft.waypoints
    while not route.is_empty() and planar(raft.position,route[0])<.7: route.pop_front()
    if route.is_empty() and reward_resolved():
        route_around_dock(tribe)
    if not route.is_empty(): target=route[0]
    var gap := planar(raft.position,target)
    var direction: Vector3=raft.position.direction_to(target)
    for other: String in rafts:
        if other==tribe or (not route.is_empty() and not bool(raft.get("dock_route",false))): continue
        var offset: Vector3=raft.position-rafts[other].position
        var separation := Vector2(offset.x,offset.z).length()
        if separation>.01 and separation<10:
            direction+=offset.normalized()*(10-separation)*.24
    var desired_heading := atan2(direction.x,direction.z)
    var reversing := float(raft.get("reverse_remaining",0))>0
    if reversing: desired_heading=float(raft.heading)
    var turn_error := absf(angle_difference(float(raft.heading),desired_heading))
    var previous_heading := float(raft.heading)
    raft.heading=rotate_toward(float(raft.heading),desired_heading,STEP*.9)
    var travel_speed := float(raft.momentum)*(1.0 if reversing else clampf(cos(turn_error),.12,1))
    if reward_resolved() and route.is_empty(): travel_speed=minf(travel_speed,sqrt(maxf(0,gap)*1.1))
    var previous: Vector3=raft.position
    var travel := minf(travel_speed*STEP,float(raft.reverse_remaining) if reversing else gap)
    var candidate := previous+Vector3(sin(float(raft.heading)),0,cos(float(raft.heading)))*travel*(-1.0 if reversing else 1.0)
    var blocked := not raft_motion_clear(tribe,candidate,access)
    var contacted := blocked
    if blocked and absf(angle_difference(previous_heading,float(raft.heading)))>.00001:
        # A stern sweep can block turning while the current heading is safe.
        # Keep actual forward clearance instead of wedging both nearby hulls.
        raft.heading=previous_heading
        candidate=previous+Vector3(sin(previous_heading),0,cos(previous_heading))*travel*(-1.0 if reversing else 1.0)
        blocked=not raft_motion_clear(tribe,candidate,access)
    if not blocked: raft.position=candidate
    else:
        raft.momentum=0.0
        raft.heading=previous_heading
        if reversing: raft.reverse_remaining=0.0
    if not blocked: raft.momentum=minf(float(raft.momentum),travel_speed)
    raft.velocity=(raft.position-previous)/STEP
    var actual := (raft.position as Vector3).distance_to(previous)
    raft.speed=actual/STEP
    raft.distance+=actual
    if reversing:
        raft.reverse_remaining=maxf(0,float(raft.reverse_remaining)-actual)
        if float(raft.reverse_remaining)<.02:
            raft.reverse_remaining=0.0
            raft.momentum=0.0
    raft.max_speed=maxf(float(raft.max_speed),actual/STEP)
    # Tiny successful collision-boundary steps are not meaningful route progress.
    if not raft.has("progress_position"): raft["progress_position"]=previous
    raft["collision_seen"]=bool(raft.get("collision_seen",false)) or contacted
    raft.blocked_seconds=float(raft.blocked_seconds)+STEP
    if float(raft.blocked_seconds)>=3.0:
        # A real outboard detour, not relocation or a fictitious distance award.
        if not reversing and bool(raft.collision_seen) and contributors>0 and planar(raft.position,raft.progress_position)<.35 and raft.repaths<3:
            # Backwater uses the same accepted stroke force, continuous hull
            # collision checks and actual distance. Clearance is not relocation.
            raft["reverse_remaining"]=3.5
            raft.momentum=0.0
            raft.repaths+=1
            event("vessel_backwater",int(raft.crew[0]))
        raft.blocked_seconds=0.0
        raft.progress_position=raft.position
        raft.collision_seen=false
    if reward_resolved() and route.is_empty() and gap<2.8:
        raft.arrived=true
        raft.state="grounded"
        raft.speed=0.0
        raft.momentum=0.0
        raft.velocity=Vector3.ZERO
        raft.arrival_time=elapsed
        assign_unloading(tribe)
        if not raft.crew.is_empty(): event("raft_landed",int(raft.crew[0]))

func raft_motion_clear(tribe: String, candidate: Vector3, access: Callable) -> bool:
    if not vessel_clear(tribe,candidate): return false
    if not access.is_valid(): return true
    var raft: Dictionary=rafts[tribe]
    raft["candidate"]=candidate
    return bool(access.call(int(raft.crew[0]) if not raft.crew.is_empty() else int(configuration.selected),"vessel"))

func route_around_dock(tribe: String) -> void:
    var raft: Dictionary=rafts[tribe]
    var start: Vector3=raft.position
    var finish: Vector3=raft.stop_position
    var segment := Vector2(finish.x-start.x,finish.z-start.z)
    if segment.length_squared()<.01 or start.z>=reward_position.z+11: return
    var offset := Vector2(reward_position.x-start.x,reward_position.z-start.z)
    var nearest := Vector2(start.x,start.z)+segment*clampf(offset.dot(segment)/segment.length_squared(),0,1)
    # Dock half-width2.5m plus the rotating raft corner4.6m and clearance.
    if nearest.distance_to(Vector2(reward_position.x,reward_position.z))>=9: return
    var side := float(raft.dock_side)
    # Independent resolved-reward lanes prevent two same-side hulls converging
    # on one intermediate point. This cannot affect the contested reward race.
    var lane := 9.5+float(rafts.keys().find(tribe))*10.5
    var outboard := reward_position.x+side*lane
    raft["dock_route"]=true
    raft.waypoints.append(Vector3(outboard,start.y,start.z))
    raft.waypoints.append(Vector3(outboard,start.y,reward_position.z+11))
    if not raft.crew.is_empty(): event("vessel_dock_clearance",int(raft.crew[0]))

static func planar(a: Vector3,b: Vector3) -> float:
    return Vector2(a.x-b.x,a.z-b.z).length()

func vessel_clear(tribe: String, candidate: Vector3) -> bool:
    # Conservative oriented-rectangle separation, evaluated along a <=.074m step.
    var raft: Dictionary=rafts[tribe]
    var forward := Vector2(sin(float(raft.heading)),cos(float(raft.heading)))
    var side := Vector2(forward.y,-forward.x)
    for other: String in rafts:
        if other==tribe: continue
        var other_raft: Dictionary=rafts[other]
        var other_forward := Vector2(sin(float(other_raft.heading)),cos(float(other_raft.heading)))
        var other_side := Vector2(other_forward.y,-other_forward.x)
        var offset := Vector2(candidate.x-other_raft.position.x,candidate.z-other_raft.position.z)
        var separated := false
        for axis: Vector2 in [forward,side,other_forward,other_side]:
            var extent := absf(axis.dot(forward))*4.12+absf(axis.dot(side))*2.07+absf(axis.dot(other_forward))*4.12+absf(axis.dot(other_side))*2.07
            if absf(offset.dot(axis))>extent: separated=true
        if not separated: return false
    return true

func assign_unloading(tribe: String) -> void:
    var raft: Dictionary=rafts[tribe]
    if raft.crew.is_empty(): return
    for index in raft.cargo_ids.size():
        var id := int(raft.crew[index%raft.crew.size()])
        actors[id].cargo_batch.append(raft.cargo_ids[index])
    if reward.location=="raft" and reward.tribe==tribe:
        reward.location="carried"
        reward.carrier=int(raft.crew[0])

func strategy(tribe: String) -> void:
    var raft: Dictionary=rafts[tribe]
    if raft.state!="underway": return
    var paddlers := 0
    for id_value in raft.crew: paddlers+=int(actors[int(id_value)].paddling)
    if paddlers<2:
        for id_value in raft.crew:
            var id := int(id_value)
            if id!=int(configuration.selected): actors[id].paddling=true
    if raft.crew.size()<=2: return
    var best := 0
    var gain := 3.0
    for id_value in raft.crew:
        var id := int(id_value)
        if id==int(configuration.selected) or elapsed<float(actors[id].reconsider): continue
        var gap: float=actors[id].position.distance_to(objective(tribe))
        var saved := gap/maxf(.5,float(raft.speed))-gap/swim_speed(id)
        var willingness := (rating(id,"risk")+rating(id,"awareness"))*.12
        if gap<28 and saved+willingness>gain:
            best=id
            gain=saved+willingness
    if best!=0: leave(best)

func result() -> Dictionary:
    return {"version":2,"configuration":configuration.duplicate(true),"selected":configuration.selected,"seed":configuration.seed,"rng_state":rng.state,"scramble":scramble_result.duplicate(true),"reward":reward.duplicate(true),"contestants":actors.duplicate(true),"rafts":rafts.duplicate(true),"events":events.duplicate(true),"elapsed":elapsed,"phase":phase}
