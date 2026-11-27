class_name MarooningRace
extends RefCounted
## Fixed-step transient authority. Physical adapter supplies validated world positions.
enum Phase { BOARDING, RAFT_RACE, CAMP_APPROACH, ARRIVAL_COMPLETE }
const STEP := 1.0 / 60.0
const BEAT := 1.6
const PERSON_KG := 75.0
var phase := Phase.BOARDING
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
var reward := {"id":"fishing-equipment-preview","tribe":"","actor":0,"time":0.0,"method":"","mass_kg":8.0,"carrier":0,"secured":false,"location":"platform"}
var reward_position := Vector3.ZERO
var boarding_seconds := 60.0
var assembly_minimum := 12.0
var timing_scale := 1.0
var _beat := -1
var _strategy_at := 0.0
var feedback := "Aim for the centre · one stroke per cycle"

func configure(config: Dictionary, roster: Dictionary, cargo: Dictionary, routes: Dictionary, reward_point: Vector3) -> void:
    configuration = config.duplicate(true)
    scramble_result = cargo.duplicate(true)
    rng.seed = int(config.seed)
    reward_position = reward_point
    for id: int in roster:
        actors[id] = roster[id].duplicate(true)
        actors[id].merge({"raft":"","mode":"walking","fatigue":0.0,"paddling":true,"power":0.0,"beat":-1,"strokes":0,"perfect":0,"good":0,"missed":0,"swim_distance":0.0,"boardings":0,"departures":0,"force_total":0.0,"reconsider":0.0})
    for tribe: Dictionary in config.tribes:
        for index in tribe.members.size():
            actors[int(tribe.members[index])]["seat_index"] = index
        var route: Dictionary = routes[tribe.id]
        var mass := 0.0
        for item: Dictionary in cargo.secured[tribe.id]:
            mass += float(MarooningSupplyCatalog.definitions()[item.type].mass_kg)
        rafts[tribe.id] = {"id":route.raft_id,"position":route.raft_mount,"heading":0.0,"speed":0.0,"crew":[],"capacity":tribe.members.size(),"cargo_kg":mass,"mass_kg":180.0+mass,"draft":0.0,"sync":0.0,"distance":0.0,"stop_position":Vector3(route.destination.x,.55,152) if route.route_id == "player-landing" else route.destination,"destination":route.destination,"destination_id":route.route_id,"arrived":false,"arrival_time":-1.0,"strategy_at":0.0,"max_speed":0.0,"peak_mass_kg":180.0+mass,"paddler_seconds":0.0,"crew_seconds":0.0}
        update_mass(rafts[tribe.id])

static func seat(index: int) -> Vector3:
    return Vector3(-1.4 if index % 2 == 0 else 1.4,.25,-2.9 + (index / 2) * 1.35)

func rating(id: int, key: String) -> float:
    return clampf(float(actors[id].attributes.get(key,5)),1,10)

func boarding_point(tribe: String) -> Vector3:
    var raft: Dictionary = rafts[tribe]
    return raft.position + Vector3(0,.1,-4.0).rotated(Vector3.UP,raft.heading)

func boarding_access(id: int) -> Vector3:
    var actor: Dictionary = actors[id]
    var raft: Dictionary = rafts[actor.tribe]
    var nearest := boarding_point(actor.tribe)
    var distance: float = actor.position.distance_to(nearest)
    for side: float in [-2.4,2.4]:
        for z: float in [-2.0,2.0]:
            var point := (raft.position as Vector3)+Vector3(side,.1,z).rotated(Vector3.UP,float(raft.heading))
            var current: float = actor.position.distance_to(point)
            if current<distance:
                nearest=point
                distance=current
    return nearest

func can_board(id: int) -> bool:
    var actor: Dictionary = actors[id]
    var raft: Dictionary = rafts[actor.tribe]
    return actor.raft.is_empty() and actor.mode != "arrived" and not raft.arrived and raft.crew.size() < int(raft.capacity) and actor.position.distance_to(boarding_access(id)) <= 2.7

func request_board(id: int, accessible := true) -> bool:
    if suspended or not accessible or not can_board(id) or pending.has(id):
        return false
    pending[id] = elapsed + .7
    return true

func leave(id: int) -> bool:
    var actor: Dictionary = actors[id]
    if suspended or actor.raft.is_empty():
        return false
    var raft: Dictionary = rafts[actor.raft]
    var index := int(actor.seat_index)
    actor.position = raft.position + Vector3(-3.0 if index % 2 == 0 else 3.0,-1.6,(index/2-(int(raft.capacity)-1)/4.0)*1.0).rotated(Vector3.UP,raft.heading)
    raft.crew.erase(id)
    actor.raft = ""
    actor.mode = "swimming"
    actor.power = 0.0
    actor.departures += 1
    actor.reconsider = elapsed + 12
    event("disembarked",id)
    update_mass(raft)
    return true

func stroke(id: int) -> String:
    var actor: Dictionary = actors[id]
    if suspended or phase == Phase.BOARDING or actor.raft.is_empty() or not actor.paddling or actor.beat == _beat:
        return ""
    var error := absf(fmod(elapsed,BEAT) / BEAT - .5)
    var grade := "Perfect" if error <= .065 * timing_scale else ("Good" if error <= .17 * timing_scale else "Early/Late")
    apply_stroke(id,{"Perfect":1.5,"Good":1.1,"Early/Late":.65}[grade],grade)
    feedback = grade
    return grade

func apply_stroke(id: int, quality: float, grade: String) -> void:
    var actor: Dictionary = actors[id]
    actor["stroke_phase"] = fmod(elapsed,BEAT)/BEAT
    actor.beat = _beat
    actor.strokes += 1
    actor.perfect += int(grade == "Perfect")
    actor.good += int(grade == "Good")
    actor.power = quality * (65.0 + rating(id,"strength") * 9.0) * (1.0 - actor.fatigue * .35) * clampf(1.1 - rating(id,"laziness") * .035,.75,1.1)
    actor.force_total += actor.power

func claim(id: int, accessible := true) -> bool:
    if suspended or phase == Phase.BOARDING or not accessible or not reward.tribe.is_empty():
        return false
    var actor: Dictionary = actors[id]
    if actor.position.distance_to(reward_position) > 4.5:
        return false
    reward.merge({"tribe":actor.tribe,"actor":id,"time":elapsed,"method":"raft" if not actor.raft.is_empty() else "swim"},true)
    if not actor.raft.is_empty():
        rafts[actor.tribe].cargo_kg += float(reward.mass_kg)
        reward.merge({"secured":true,"location":"raft"},true)
    else:
        reward.merge({"carrier":id,"location":"carried"},true)
    event("reward_claimed",id)
    return true

func event(action: String, id: int) -> void:
    var witnesses: Array[int] = []
    for other: int in actors:
        if other != id and actors[other].position.distance_to(actors[id].position) < 8:
            witnesses.append(other)
    events.append({"action":action,"actor":id,"tribe":actors[id].tribe,"time":elapsed,"nearby_witnesses":witnesses,"reward_id":reward.id if action == "reward_claimed" else ""})
    if events.size() > 512:
        events.pop_front()

func swim_speed(id: int) -> float:
    # No swimming attribute exists: endurance, speed and balance are approved proxies.
    return clampf(1.5 + rating(id,"endurance") * .07 + rating(id,"speed") * .045 + rating(id,"balance") * .015,1.8,2.8) * (1 - actors[id].fatigue * .18) * (.94 if int(reward.carrier) == id else 1.0)

func objective(tribe: String) -> Vector3:
    return reward_position if reward.tribe.is_empty() else rafts[tribe].destination

func arrival_point(id: int) -> Vector3:
    var actor: Dictionary = actors[id]
    var capacity := int(rafts[actor.tribe].capacity)
    return rafts[actor.tribe].destination + Vector3((float(actor.seat_index)-(capacity-1)*.5)*1.15,0,0).rotated(Vector3.UP,float(rafts[actor.tribe].heading))

func actor_objective(id: int) -> Vector3:
    return reward_position if reward.tribe.is_empty() else arrival_point(id)

func update_mass(raft: Dictionary) -> void:
    raft.mass_kg = 180.0 + float(raft.cargo_kg) + raft.crew.size() * PERSON_KG
    raft.peak_mass_kg = maxf(float(raft.peak_mass_kg),float(raft.mass_kg))
    raft.draft = clampf((float(raft.mass_kg)-180.0) / 4000.0,0,.32)

func advance(delta: float, access: Callable = Callable()) -> void:
    if suspended or phase == Phase.ARRIVAL_COMPLETE or delta <= 0:
        return
    accumulator += minf(delta,.25)
    while accumulator + .000001 >= STEP:
        accumulator -= STEP
        step(access)

func step(access: Callable) -> void:
    elapsed += STEP
    var ids := actors.keys()
    ids.sort()
    for id: int in ids:
        if pending.has(id) and elapsed >= float(pending[id]):
            if can_board(id) and (not access.is_valid() or access.call(id,"board")):
                var actor: Dictionary = actors[id]
                actor.raft = actor.tribe
                actor.mode = "aboard"
                rafts[actor.tribe].crew.append(id)
                actor.boardings += 1
                if int(reward.carrier) == id:
                    rafts[actor.tribe].cargo_kg += float(reward.mass_kg)
                    reward.merge({"carrier":0,"secured":true,"location":"raft"},true)
                    event("reward_secured",id)
                event("boarded",id)
            pending.erase(id)
    if phase == Phase.BOARDING:
        var assembled := true
        for actor_id: int in actors:
            var actor: Dictionary = actors[actor_id]
            if actor.raft.is_empty() and (actor_id != int(configuration.selected) and int(actor.boardings)==0 or not (actor.position.y < .3 and (absf(actor.position.x)>8 or actor.position.z>18))):
                assembled = false
        # All NPCs try to assemble; the human may deliberately choose independent swimming.
        if elapsed >= boarding_seconds or (elapsed >= assembly_minimum and assembled):
            phase = Phase.RAFT_RACE

    if phase == Phase.BOARDING:
        for raft: Dictionary in rafts.values():
            update_mass(raft)
            for id: int in raft.crew:
                actors[id].position = raft.position + seat(int(actors[id].seat_index)).rotated(Vector3.UP,raft.heading) - Vector3.UP*float(raft.draft)
        return
    var beat := int(elapsed / BEAT)
    if beat != _beat:
        _beat = beat
        for id: int in ids:
            var actor: Dictionary = actors[id]
            if not actor.raft.is_empty():
                if actor.beat < beat - 1 and actor.paddling:
                    actor.missed += 1
                actor.power = 0.0
                actor["stroke_due"] = beat * BEAT + BEAT * clampf(.5 + rng.randf_range(-.22,.22) * (1.25-rating(id,"dexterity")*.08),.15,.85)
    for id: int in ids:
        var actor: Dictionary = actors[id]
        if not actor.raft.is_empty():
            if id != int(configuration.selected) and actor.paddling and actor.beat != _beat and elapsed >= float(actor.get("stroke_due",INF)):
                var err := absf(float(actor.stroke_due) / BEAT - floorf(float(actor.stroke_due) / BEAT) - .5)
                apply_stroke(id,1.5 if err < .065 else (1.1 if err < .17 else .65),"Perfect" if err < .065 else ("Good" if err < .17 else "Early/Late"))
            actor.fatigue = clampf(actor.fatigue + STEP * (.0028 * (1.2-rating(id,"endurance")*.07) if actor.paddling else -.008),0,1)
        elif actor.mode == "swimming":
            actor.fatigue = clampf(actor.fatigue + STEP * .002,0,1)
        if id != int(configuration.selected) and reward.tribe.is_empty() and actor.position.distance_to(reward_position) <= 4.5:
            claim(id,not access.is_valid() or access.call(id,"claim"))
    for tribe: String in rafts:
        var raft: Dictionary = rafts[tribe]
        update_mass(raft)
        if raft.arrived:
            continue
        var force := 0.0
        var timing_quality := 0.0
        var leadership := 0.0
        for id: int in raft.crew:
            force += float(actors[id].power)
            raft.paddler_seconds += STEP * int(actors[id].paddling)
            raft.crew_seconds += STEP
            if float(actors[id].power) > 0:
                timing_quality += clampf(1.0-absf(float(actors[id].get("stroke_phase",0))-.5)*3,0,1)
            leadership = maxf(leadership,rating(id,"leader"))
        raft.sync = timing_quality / maxf(1,raft.crew.size())
        var drag := 38.0 * (1.0 + (float(raft.mass_kg)-180.0) / 1600.0)
        var acceleration := (force * (1 + (.07+leadership*.01) * float(raft.sync)) - drag * float(raft.speed) * float(raft.speed)) / float(raft.mass_kg)
        raft.speed = clampf(float(raft.speed) + acceleration * STEP,0,4.4)
        var target: Vector3 = reward_position if reward.tribe.is_empty() else raft.stop_position
        var distance: float = Vector2(target.x-raft.position.x,target.z-raft.position.z).length()
        if distance > .01:
            var direction: Vector3 = raft.position.direction_to(target)
            for other_tribe: String in rafts:
                if other_tribe == tribe:
                    continue
                var separation: Vector3 = raft.position - rafts[other_tribe].position
                var gap := separation.length()
                if gap > .01 and gap < 9:
                    direction += separation.normalized() * (9-gap)*.4
            var goal := atan2(direction.x,direction.z)
            raft.heading = rotate_toward(float(raft.heading),goal,STEP*.6)
            var travel := minf(float(raft.speed)*STEP,distance)
            var candidate: Vector3 = raft.position + Vector3(sin(float(raft.heading)),0,cos(float(raft.heading))) * travel
            var blocked := false
            for other_tribe: String in rafts:
                if other_tribe != tribe and candidate.distance_to(rafts[other_tribe].position) < 4.4:
                    blocked = true
            if not blocked:
                raft.position = candidate
            raft.distance += travel
            raft.max_speed = maxf(float(raft.max_speed),float(raft.speed))
        if not reward.tribe.is_empty() and distance < 4:
            raft.arrived = true
            raft.speed = 0.0
            raft.arrival_time = elapsed
        # Exact local anchors: never accumulate moving-platform velocities.
        for id: int in raft.crew:
            actors[id].position = raft.position + seat(int(actors[id].seat_index)).rotated(Vector3.UP,raft.heading) - Vector3.UP * float(raft.draft)
        if elapsed >= float(raft.strategy_at):
            raft.strategy_at = elapsed + 4
            strategy(tribe)
    for id: int in ids:
        var actor: Dictionary = actors[id]
        if actor.raft.is_empty() and not reward.tribe.is_empty() and Vector2(actor.position.x-arrival_point(id).x,actor.position.z-arrival_point(id).z).length() < (4.0 if id == int(configuration.selected) else .2):
            actor.mode = "arrived"
            if int(reward.carrier) == id:
                reward.merge({"carrier":0,"secured":true,"location":"shore"},true)
                event("reward_secured",id)
    if not reward.tribe.is_empty():
        phase = Phase.CAMP_APPROACH
    var selected_tribe: String = actors[int(configuration.selected)].tribe
    var complete: bool = rafts[selected_tribe].arrived
    for actor: Dictionary in actors.values():
        if actor.tribe == selected_tribe and actor.mode != "arrived":
            complete = false
    if complete:
        phase = Phase.ARRIVAL_COMPLETE

func strategy(tribe: String) -> void:
    var raft: Dictionary = rafts[tribe]
    if raft.crew.size() <= 3 or raft.arrived:
        return
    var best := 0
    var gain := 2.0
    for id: int in raft.crew:
        if id == int(configuration.selected) or elapsed < float(actors[id].reconsider):
            continue
        var distance: float = actors[id].position.distance_to(objective(tribe))
        var seconds_saved := distance / maxf(.5,float(raft.speed)) - distance / swim_speed(id)
        var willingness := (rating(id,"risk") + rating(id,"awareness")) * .15
        if distance < 32 and seconds_saved + willingness > gain:
            best = id
            gain = seconds_saved + willingness
    if best != 0:
        leave(best)

func result() -> Dictionary:
    return {"version":1,"configuration":configuration.duplicate(true),"selected":configuration.selected,"seed":configuration.seed,"rng_state":rng.state,"scramble":scramble_result.duplicate(true),"reward":reward.duplicate(true),"contestants":actors.duplicate(true),"rafts":rafts.duplicate(true),"events":events.duplicate(true),"elapsed":elapsed,"phase":phase}
