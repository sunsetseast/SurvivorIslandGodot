class_name MarooningRaceAdapter
extends Node
## Presentation and physical navigation only. Preview owns the single authority tick.
var preview: MarooningPreview
var simulation: MarooningRace
var vessels: Dictionary = {}
var reward_visual: MarooningSupplyVisual
var started := false
var transitions: Dictionary = {}
var previous_attachment: Dictionary = {}
var previous_membership: Dictionary = {}
var water_routes: Dictionary = {}
var progress: Dictionary = {}
var cargo_flights: Dictionary = {}
var feedback := ""
var takeoff_offsets: Dictionary={}
var jump_retries: Dictionary={}
var assists: Dictionary={}
func selected() -> int: return int(preview.configuration.selected)
func _ready() -> void:
    simulation=preview.session.race
    simulation.reward.id=preview.layout.reward_id
    simulation.timing_scale=clampf(float(preview.preferences.get("paddle_timing_scale",1.0)),.7,1.8)
    for tribe: Dictionary in preview.configuration.tribes:
        var raft: MarooningRaft=preload("res://marooning/raft.tscn").instantiate()
        raft.name=tribe.id
        raft.build(tribe.members,Color(tribe.color))
        preview.add_child(raft)
        vessels[tribe.id]=raft
        raft.present(simulation.rafts[tribe.id],simulation.actors,0,1)
    reward_visual=MarooningSupplyVisual.new()
    reward_visual.build("fishing")
    preview.add_child(reward_visual)
    reward_visual.hide()
    for id: int in preview.cast:
        preview.cast[id].water=CampWaterSurface.new(0,preview.layout.bed)
    set_physics_process(false)
func begin() -> void: started=true
func access(id: int, action: String) -> bool:
    var actor: CampPhysicalMotor=preview.cast[id]
    var state: Dictionary=simulation.actors[id]
    if action=="launch":
        for item: Dictionary in preview.session.scramble.items.values():
            if item.state==MarooningScramble.State.SECURED and item.tribe==state.tribe and item.get("location","")=="loading": return false
        return true
    if action=="climb":
        var check_shape := CapsuleShape3D.new()
        check_shape.radius=.35
        check_shape.height=1.69
        var check_query := PhysicsShapeQueryParameters3D.new()
        check_query.shape=check_shape
        check_query.collision_mask=1
        check_query.exclude=[vessels[state.tribe].get_rid()]
        check_query.transform.origin=state.position+Vector3.UP*.85
        return preview.get_world_3d().direct_space_state.intersect_shape(check_query,1).is_empty()
    if action=="vessel":
        var raft: Dictionary=simulation.rafts[state.tribe]
        var shape := BoxShape3D.new()
        shape.size=Vector3(3.9,.27,8)
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape=shape
        query.collision_mask=1
        query.exclude=[vessels[state.tribe].get_rid()]
        query.transform=Transform3D(Basis(Vector3.UP,float(raft.heading)),raft.get("candidate",raft.position)-Vector3.UP*(float(raft.draft)+.08))
        return preview.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
    var target: Vector3=simulation.boarding_access(id) if action=="board" else preview.layout.reward
    var query := PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.8,target+Vector3.UP*(.8 if action=="board" else 2.0),1)
    query.exclude=[vessels[state.tribe].get_rid()]
    return preview.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func board_actor(id: int) -> bool:
    if not simulation.can_board(id) or not access(id,"board"): return false
    preview.session.depart(id,"swimming")
    return simulation.request_board(id,true)
func jump_off() -> void:
    var id := selected()
    var from: Vector3=preview.cast[id].position
    var inherited: Vector3=simulation.rafts[simulation.actors[id].tribe].velocity
    if simulation.leave(id): begin_transition(id,from,simulation.actors[id].position+inherited*.85,.85,false)
func jump_deck(id: int) -> bool:
    var state: Dictionary=simulation.actors[id]
    if state.place!="deck" or transitions.has(id): return false
    var gate: Vector3=preview.routes[state.tribe].deck_access
    var body: CampPhysicalMotor=preview.cast[id]
    if MarooningRace.planar(body.position,gate)>4.2 or absf(body.position.x)<2.8:
        feedback="Use your tribe's open side ramp to jump"
        return false
    var end := Vector3(signf(gate.x)*6.25,-1.07,gate.z+(-2.8 if int(state.seat_index)%2==0 else 2.8))
    if not transition_clear(id,body.position,end,1.45,true):
        feedback="Jump access occupied; wait for clear water"
        return false
    preview.session.depart(id,"swimming")
    begin_transition(id,body.position,end,1.45,true)
    return true
func trajectory(from: Vector3, to: Vector3, t: float, seconds: float, deck: bool) -> Vector3:
    var point: Vector3=from.lerp(to,t)
    if deck:
        point.x=lerpf(from.x,to.x,minf(t*1.55,1))
        point.z=lerpf(from.z,to.z,smoothstep(.36,1,t))
    # Exact endpoint and a gravity-consistent vertical parabola.
    var v := (to.y-from.y)/seconds+4.9*seconds
    point.y=from.y+v*t*seconds-4.9*t*t*seconds*seconds
    return point
func transition_clear(id: int, from: Vector3, to: Vector3, seconds: float, deck: bool) -> bool:
    var body: CampPhysicalMotor=preview.cast[id]
    var shape := CapsuleShape3D.new()
    shape.radius=.35
    shape.height=1.69
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape=shape
    query.collision_mask=1|2|4
    query.exclude=[body.get_rid()]
    # The takeoff support is permitted only at t=0; all later flight is swept.
    var prior := trajectory(from,to,.025,seconds,deck)
    for i in range(2,65):
        var point := trajectory(from,to,float(i)/64,seconds,deck)
        query.transform.origin=prior+Vector3.UP*.85
        query.motion=point-prior
        var fractions := preview.get_world_3d().direct_space_state.cast_motion(query)
        if not fractions.is_empty() and fractions[0]<.999: return false
        prior=point
    return true
func begin_transition(id: int, from: Vector3, to: Vector3, seconds: float, deck: bool) -> void:
    previous_attachment[id]=false
    previous_membership[id]=false
    simulation.actors[id].mode="jumping"
    transitions[id]={"from":from,"to":to,"at":preview.session.elapsed,"seconds":seconds,"deck":deck}
    var body: CampHumanoidMotor=preview.cast[id]
    body.raft_attached=true
    body.velocity=Vector3.ZERO
    body.planar=Vector3.ZERO
    body.set_motion(&"Tread")
    if id==selected(): preview.touch.cancel()
func prepare(delta: float) -> void:
    started=preview.session.started
    for id: int in preview.cast:
        var state: Dictionary=simulation.actors[id]
        var body: CampHumanoidMotor=preview.cast[id]
        if not state.raft.is_empty() or simulation.pending.has(id) or transitions.has(id) or assists.has(id): continue
        state.position=body.position
        state.velocity=body.get_real_velocity()
        if state.place=="deck":
            if absf(body.position.x)<3.6 and absf(body.position.y-preview.layout.deck_y)<.35: state.last_deck_position=body.position
            if body.position.y<.3 and absf(body.position.x)>4.5: preview.session.depart(id,"swimming")
        else:
            state.mode="swimming" if body.swimming() else "walking"
            if body.swimming():
                state.swim_distance+=body.get_real_velocity().length()*delta
                body.movement_speed_multiplier=simulation.swim_speed(id)/CampPhysicalMotor.SWIM_SPEED
            else: body.movement_speed_multiplier=.9 if not state.cargo_batch.is_empty() else 1.0
        if id!=selected() and preview.session.state==MarooningSession.State.ACTIVE: move_npc(id,delta)
func move_npc(id: int, delta: float) -> void:
    var state: Dictionary=simulation.actors[id]
    var body: CampHumanoidMotor=preview.cast[id]
    var traffic := preview.scramble.traffic
    if state.arrived:
        var activity := simulation.arrival_point(id)
        var offset := activity-body.position
        offset.y=0
        for other: int in preview.cast:
            if other==id or not simulation.actors[other].arrived: continue
            var away: Vector3=body.position-preview.cast[other].position
            away.y=0
            if away.length()>.01 and away.length()<1.2: offset+=away.normalized()*(1.2-away.length())*2
        body.walk_direction(offset.normalized()*.65 if MarooningRace.planar(body.position,activity)>1.35 else Vector3.ZERO,false,delta)
        if MarooningRace.planar(body.position,activity)<=1.35: body.set_motion(&"Idle")
        return
    if state.place=="deck":
        if not preview.session.wants_departure(id): return
        var gate: Vector3=preview.routes[state.tribe].deck_access
        if preview.scramble.simulation.phase==MarooningScramble.Phase.SCRAMBLE_ACTIVE and not preview.scramble.simulation.carried(id).is_empty() and simulation.elapsed<preview.session.departure_time(id)+5 and preview.scramble.simulation.eligible(id):
            preview.scramble.decide(id)
            traffic.step(id,delta)
            return
        traffic.release(id)
        var takeoff := gate+Vector3(0,0,float(takeoff_offsets.get(id,0)))
        traffic.target(id,takeoff,"departing")
        traffic.step(id,delta)
        if MarooningRace.planar(body.position,takeoff)<.4 and simulation.elapsed>=float(jump_retries.get(id,0)):
            if not jump_deck(id):
                var offset := float(takeoff_offsets.get(id,0))
                takeoff_offsets[id]=.7 if is_zero_approx(offset) else (-.7 if offset>0 else 0.0)
                jump_retries[id]=simulation.elapsed+1.0
                simulation.event("takeoff_access_retry",id)
        return
    if preview.scramble.agents.has(id): preview.scramble.agents[id].avoidance_enabled=false
    var raft: Dictionary=simulation.rafts[state.tribe]
    var early: bool=state.objective=="early_swim" and not simulation.reward_resolved()
    var goal := simulation.actor_objective(id)
    if not early and raft.state=="moored":
        var access_index := maxi(0,simulation.nearest_access(id,true))
        goal=simulation.to_world(state.tribe,MarooningRace.access_points()[access_index])
        if simulation.can_board(id) and simulation.elapsed>=float(state.reconsider):
            if board_actor(id): return
    elif not early and raft.state=="underway" and int(state.boardings)==0 and body.position.distance_to(simulation.boarding_access(id))<12:
        goal=simulation.boarding_access(id)
        if simulation.can_board(id) and simulation.elapsed>=float(state.reconsider):
            if board_actor(id): return
    # Always clear the ship and each physical vessel from outside, then turn.
    if body.position.z<22 and absf(body.position.x)<9.2:
        var side := signf(preview.routes[state.tribe].deck_access.x)
        goal=Vector3(side*9.8,-1.07,body.position.z)
    elif body.position.z<22 and (early or raft.state!="moored"):
        goal=Vector3(body.position.x,-1.07,25)
    elif raft.arrived:
        var local := simulation.to_local(state.tribe,body.position)
        if absf(local.x)<4.5 and local.z<6.0:
            goal=simulation.to_world(state.tribe,Vector3(-4.6 if local.x<0 else 4.6,-1.5,maxf(local.z,5.8)))
    if water_routes.has(id) and simulation.elapsed<float(water_routes[id].until): goal=water_routes[id].point
    elif water_routes.has(id): water_routes.erase(id)
    var direction := goal-body.position
    direction.y=0
    direction=direction.normalized()*minf(1,direction.length()/.8)
    var forward := direction.normalized()
    for other: int in preview.cast:
        if other==id or not simulation.actors[other].raft.is_empty(): continue
        var offset: Vector3=body.position-preview.cast[other].position
        offset.y=0
        if offset.length()>.01 and offset.length()<1.15:
            direction+=offset.normalized()*(1.15-offset.length())*1.7
            if forward.dot(-offset.normalized())>.6: direction+=Vector3(forward.z,0,-forward.x)*.65
    body.walk_direction(direction.limit_length(),not body.swimming(),delta)
    watch_progress(id,goal,delta)
func watch_progress(id: int, goal: Vector3, delta: float) -> void:
    var body: CampPhysicalMotor=preview.cast[id]
    var gap := MarooningRace.planar(body.position,goal)
    if not progress.has(id): progress[id]={"gap":gap,"seconds":0.0,"attempts":0,"goal":goal,"total_stall":0.0}
    var row: Dictionary=progress[id]
    if gap<float(row.gap)-.18:
        row.total_stall=0.0
    elif gap>1.2: row.total_stall+=delta
    if gap<float(row.gap)-.18 or MarooningRace.planar(row.goal,goal)>2:
        row.gap=gap
        row.seconds=0.0
        row.goal=goal
    elif gap>1.2:
        row.seconds+=delta
    if float(row.seconds)>4:
        row.attempts+=1
        row.seconds=0.0
        var offset := Vector3(-1.5 if int(row.attempts)%2==0 else 1.5,0,1.5)
        water_routes[id]={"point":body.position+offset,"until":simulation.elapsed+2}
        simulation.event("navigation_retry",id)
    if float(row.total_stall)>=45 and int(row.attempts)>=8 and not assists.has(id):
        if safe_assist(id,goal,int(row.attempts),"45s_without_route_progress"):
            row.total_stall=0.0
            row.seconds=0.0
func safe_assist(id: int,goal: Vector3,attempts: int,reason: String) -> bool:
    # Last resort only: never advance a human or award/finish an objective here.
    if id==selected() or assists.has(id) or simulation.actors[id].arrived: return false
    var body: CampPhysicalMotor=preview.cast[id]
    var state: Dictionary=simulation.actors[id]
    var from := body.position
    var forward := goal-from
    forward.y=0
    forward=forward.normalized()
    var shape := CapsuleShape3D.new()
    shape.radius=.37
    shape.height=1.69
    var chosen := Vector3.INF
    for offset: Vector3 in [Vector3(forward.z,0,-forward.x)*2.4,Vector3(-forward.z,0,forward.x)*2.4,-forward*2.4]:
        var point := from+offset
        if offset.dot(forward)>.05: continue
        if point.distance_to(simulation.reward_position)<6 or MarooningRace.planar(point,simulation.rafts[state.tribe].shore_center)<8: continue
        if state.place=="deck":
            if absf(point.x)>3.2 or point.z< -4 or point.z>8: continue
            var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point-Vector3.UP,1)
            var hit := preview.get_world_3d().direct_space_state.intersect_ray(ray)
            if hit.is_empty() or absf(hit.position.y-preview.layout.deck_y)>.3 or hit.normal.y<.7: continue
            point.y=hit.position.y+.035
        else:
            if preview.layout.bed(point.x,point.z)>-.3: continue
            point.y=maxf(-1.07,preview.layout.bed(point.x,point.z)+.035)
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape=shape
        query.collision_mask=1|2|4
        query.exclude=[body.get_rid()]
        query.transform.origin=point+Vector3.UP*.85
        if not preview.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
        chosen=point
        break
    if chosen==Vector3.INF: return false
    var held := preview.session.scramble.carried(id)
    var batch: Array=state.cargo_batch.duplicate()
    if state.place=="deck": preview.session.scramble.release_on_deck(id,state.last_deck_position,"exceptional_local_recovery")
    assists[id]=true
    body.locomotion_suspended=true
    var meshes: Array[Node]=body.presentation.find_children("*","GeometryInstance3D",true,false)
    var tween := create_tween()
    tween.set_parallel(true)
    for mesh: GeometryInstance3D in meshes: tween.tween_property(mesh,"transparency",1.0,.15)
    tween.chain().tween_callback(func() -> void:
        body.position=chosen
        body.velocity=Vector3.ZERO
        body.planar=Vector3.ZERO
        body.reset_physics_interpolation()
        state.position=chosen
        state.recovered=true
        preview.session.recoveries.append({"actor":id,"from":from,"to":chosen,"elapsed":simulation.elapsed,"reason":reason,"attempts":attempts,"ordinary_cargo_set_down":held,"secured_batch":batch,"reward_carrier":int(simulation.reward.carrier)==id,"objective_awarded":false})
        simulation.event("exceptional_local_recovery",id))
    for mesh: GeometryInstance3D in meshes: tween.parallel().tween_property(mesh,"transparency",0.0,.25)
    tween.chain().tween_callback(func() -> void:
        body.locomotion_suspended=preview.session.suspended
        assists.erase(id))
    return true
func present(delta: float) -> void:
    for tribe: String in vessels: vessels[tribe].present(simulation.rafts[tribe],simulation.actors,simulation.elapsed,delta)
    for id: int in preview.cast:
        var state: Dictionary=simulation.actors[id]
        var body: CampHumanoidMotor=preview.cast[id]
        var attached: bool=not state.raft.is_empty() or simulation.pending.has(id)
        if id==selected(): preview.player.camera_vessel=vessels[state.tribe] if not state.raft.is_empty() else null
        if transitions.has(id):
            var row: Dictionary=transitions[id]
            var t := clampf((simulation.elapsed-float(row.at))/float(row.seconds),0,1)
            body.position=trajectory(row.from,row.to,t,row.seconds,row.deck)
            state.position=body.position
            if t>=1:
                transitions.erase(id)
                state.mode="swimming"
                body.raft_attached=false
                body.velocity=Vector3.ZERO
                body.planar=Vector3.ZERO
            continue
        if bool(previous_membership.get(id,false)) and state.raft.is_empty():
            # Core chose a legal outboard disembark point. Present the whole jump.
            begin_transition(id,body.position,state.position+(simulation.rafts[state.tribe].velocity as Vector3)*.85,.85,false)
            previous_attachment[id]=false
            continue
        body.raft_attached=attached
        if attached:
            body.position=state.position
            body.set_heading(float(simulation.rafts[state.tribe].heading))
            body.presentation.rotation.x=0
            body.set_motion(&"Walk" if simulation.pending.has(id) and simulation.elapsed-float(simulation.pending[id].started)>.65 else &"Seated")
            if id==selected() and not bool(previous_attachment.get(id,false)):
                preview.touch.cancel()
                preview.player.yaw=preview.player.rendered_yaw()+angle_difference(preview.player.rendered_yaw(),float(simulation.rafts[state.tribe].heading)+PI)
                preview.player.pitch=-.32
        previous_attachment[id]=attached
        previous_membership[id]=not state.raft.is_empty()
        if preview.session.state==MarooningSession.State.COMPLETE and id!=selected() and state.arrived:
            body.walk_direction(Vector3.ZERO,false,delta)
            body.set_motion(&"Idle")
        if body.has_meta("marooning_pose"):
            var pose: MarooningPose=body.get_meta("marooning_pose")
            pose.state=state
            pose.time=simulation.elapsed
            pose.grips.clear()
            if not state.raft.is_empty() and float(state.power)>0:
                var skeleton: Skeleton3D=body.presentation.skeleton
                var paddle_node: Node3D=vessels[state.tribe].paddles[id]
                pose.grips.append(skeleton.to_local(paddle_node.to_global(Vector3(0,-.15,0))))
                pose.grips.append(skeleton.to_local(paddle_node.to_global(Vector3(0,.12,0))))
            pose.held=not preview.scramble.simulation.carried(id).is_empty() or not state.cargo_batch.is_empty()
    attach_cargo(delta)
    var reward: Dictionary=simulation.reward
    var package := preview.bay.get_node_or_null("IllustrativeFishingPackage")
    if package!=null: package.hide()
    reward_visual.show()
    if reward.status!="claimed": reward_visual.position=preview.layout.reward+Vector3.UP*.25
    if reward.status=="claimed":
        if int(reward.carrier)!=0: reward_visual.position=preview.cast[int(reward.carrier)].position+Vector3(0,.9,.45)
        elif reward.location=="raft": reward_visual.position=simulation.to_world(reward.tribe,Vector3(0,.4,3.1))
        else: reward_visual.position=simulation.rafts[reward.tribe].shore_center+Vector3(2.8,.25,1)
    if preview.session.state==MarooningSession.State.COMPLETE:
        preview.set_meta("marooning_result",preview.session.result())
func haul_points(tribe: String,slot: Vector3) -> Array[Vector3]:
    var station: Vector3=preview.session.scramble.stations[tribe]
    var gate: Vector3=preview.routes[tribe].deck_access
    var side := signf(gate.x)
    return [station+Vector3(side*.15,.4,.6),Vector3(side*3.7,2.07,gate.z-.78),Vector3(side*6.75,.82,gate.z-.78),simulation.to_world(tribe,Vector3(0,.22,-3.6)),slot]
func on_polyline(points: Array[Vector3],fraction: float) -> Vector3:
    var length := 0.0
    for i in range(1,points.size()): length+=points[i-1].distance_to(points[i])
    var travel := length*clampf(fraction,0,1)
    for i in range(1,points.size()):
        var segment := points[i-1].distance_to(points[i])
        if travel<=segment: return points[i-1].lerp(points[i],travel/maxf(.001,segment))
        travel-=segment
    return points.back()
func attach_cargo(delta: float) -> void:
    var counts := {}
    for id: String in preview.scramble.simulation.items:
        var item: Dictionary=preview.scramble.simulation.items[id]
        if item.state!=MarooningScramble.State.SECURED: continue
        var index := int(counts.get(item.tribe,0))
        counts[item.tribe]=index+1
        var visual: MarooningSupplyVisual=preview.scramble.visuals[id]
        var raft: Dictionary=simulation.rafts[item.tribe]
        var local_seat := MarooningRace.seat(index%int(raft.capacity))
        var slot := simulation.to_world(item.tribe,Vector3(local_seat.x+float(index/int(raft.capacity)%2)*.22-.11,.16+float(index/(int(raft.capacity)*2))*.14,local_seat.z-.22))
        var carrier := 0
        for actor_id: int in simulation.actors:
            if simulation.actors[actor_id].cargo_batch.has(id): carrier=actor_id
        var location: String=item.get("location","raft")
        var token := location+str(carrier)
        if location=="loading":
            if visual.get_parent()!=preview: visual.reparent(preview,true)
            var fraction := (simulation.elapsed-float(item.secured_at))/MarooningSession.HAUL_SECONDS
            visual.position=on_polyline(haul_points(item.tribe,slot),fraction)
            visual.scale=Vector3.ONE*.58
            continue
        if location=="shore":
            slot=raft.shore_center+Vector3(3.7+(index%3)*.45,.1+(index/9)*.3,-1+(index/3%3)*.55)
        elif carrier!=0:
            var body: CampHumanoidMotor=preview.cast[carrier]
            var skeleton: Skeleton3D=body.presentation.skeleton
            var hand := skeleton.find_bone("hand_r")
            slot=(skeleton.global_transform*skeleton.get_bone_global_pose(hand)).origin
        if not cargo_flights.has(id) or cargo_flights[id].token!=token:
            cargo_flights[id]={"token":token,"from":visual.global_position,"progress":0.0}
        var flight: Dictionary=cargo_flights[id]
        flight.progress=minf(1,float(flight.progress)+delta/.65)
        if carrier!=0 and float(flight.progress)>=1 and location!="shore":
            var item_copy := item.duplicate()
            item_copy.actor=carrier
            preview.scramble.attach_carried(visual,item_copy)
            var grip := MarooningSupplyVisual.carry_grip(item.type)
            visual.scale=Vector3.ONE*.58
            visual.position=-(visual.basis*(grip.point as Vector3))+Vector3(0,float(simulation.actors[carrier].cargo_batch.find(id))*.12,0)
        else:
            if visual.get_parent()!=preview: visual.reparent(preview,true)
            visual.global_position=(flight.from as Vector3).lerp(slot,flight.progress)
            visual.scale=Vector3.ONE*.58
            visual.rotation.y=float(raft.heading)
func toggle_rest() -> void:
    simulation.set_rest(selected(),simulation.actors[selected()].paddling)
func review_state() -> Dictionary:
    return {"transitions":transitions.size(),"navigation":progress.duplicate(true)}
