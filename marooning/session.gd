class_name MarooningSession
extends RefCounted
## One clock, actor table, item ledger and journal for concurrent marooning.
enum State { INTRO, READY, COUNTDOWN, ACTIVE, COMPLETE }
const STEP := 1.0/60.0
const HAUL_SECONDS := 3.5
var state := State.INTRO
var elapsed := 0.0
var accumulator := 0.0
var countdown := 3.0
var suspended := false
var configuration: Dictionary
var scramble := MarooningScramble.new()
var race := MarooningRace.new()
var events: Array[Dictionary] = []
var recoveries: Array[Dictionary] = []
var routes: Dictionary
var launch_requests: Dictionary = {}
var started := false

func configure(config: Dictionary, roster: Dictionary, anchors: Array[Vector3], stations: Dictionary, access: Array[Vector3], paths: Dictionary, reward: Vector3) -> void:
    configuration=config.duplicate(true)
    routes=paths.duplicate(true)
    scramble.configure(config,roster,anchors,stations,access)
    scramble.duration=MarooningScramble.COLLECTION_SECONDS
    race.configure(config,scramble.actors,scramble.result(paths),paths,reward,true)
    scramble.events=events
    race.events=events
    race.active=false
    for id: int in race.actors:
        race.actors[id].last_deck_position=race.actors[id].position
        # Stable per-actor schedules use approved ratings, without consuming command RNG.
        var offset := float((id*17+int(config.seed)*7)%17)/17.0
        race.actors[id]["collect_until"]=clampf(48.0-race.rating(id,"risk")*1.8-race.rating(id,"leader")*.7+offset*12,18,57)
    choose_early_swimmers()

func ready() -> void:
    if state==State.INTRO:
        state=State.READY
        scramble.ready()

func start(with_countdown := true) -> void:
    if state!=State.READY: return
    countdown=3.0 if with_countdown else 0.0
    state=State.COUNTDOWN if with_countdown else State.ACTIVE
    if not with_countdown: activate()

func activate() -> void:
    state=State.ACTIVE
    started=true
    scramble.start()
    race.active=true
    race.phase=MarooningRace.Phase.RAFT_RACE

func set_suspended(value: bool) -> void:
    suspended=value
    scramble.suspended=value
    race.suspended=value
    if value: race.cancel_climbs("focus")

func advance(delta: float, supply_access: Callable = Callable(), travel_access: Callable = Callable()) -> void:
    if suspended or state in [State.INTRO,State.READY,State.COMPLETE]: return
    if state==State.COUNTDOWN:
        countdown=maxf(0,countdown-minf(maxf(delta,0),.25))
        if countdown<=.000001: activate()
        return
    accumulator+=minf(maxf(delta,0),.25)
    while accumulator+.000001>=STEP:
        accumulator-=STEP
        elapsed+=STEP
        # A completion exactly at the cutoff wins before that station locks.
        scramble.advance_to(elapsed,supply_access)
        sync_cargo()
        race.elapsed=elapsed
        evaluate_launches(travel_access)
        race.step_at(elapsed,travel_access)
        sync_cargo()
        if race.phase==MarooningRace.Phase.ARRIVAL_COMPLETE:
            state=State.COMPLETE
            for id: int in race.actors: race.cancel_force(id)
            race.event("preview_complete",int(configuration.selected))
            break

func sync_cargo() -> void:
    for raft: Dictionary in race.rafts.values():
        raft.cargo_kg=0.0
        raft.cargo_ids.clear()
    for item: Dictionary in scramble.items.values():
        if item.state!=MarooningScramble.State.SECURED: continue
        var raft: Dictionary=race.rafts[item.tribe]
        raft.cargo_ids.append(item.id)
        if not item.has("secured_at"):
            item["secured_at"]=elapsed
            item["location"]="loading"
        if item.location=="loading" and elapsed-float(item.secured_at)>=HAUL_SECONDS: item.location="raft"
        var unloader := 0
        for actor_id: int in race.actors:
            if race.actors[actor_id].cargo_batch.has(item.id): unloader=actor_id
        if unloader!=0:
            item["unloader"]=unloader
            item.location="carried"
        if raft.delivered_ids.has(item.id): item.location="shore"
        if item.location=="raft" or (item.location=="carried" and not race.actors[unloader].raft.is_empty()): raft.cargo_kg+=float(scramble.definitions[item.type].mass_kg)
    var reward: Dictionary=race.reward
    if reward.location=="raft" and not str(reward.tribe).is_empty():
        race.rafts[reward.tribe].cargo_kg+=float(reward.mass_kg)
    for raft: Dictionary in race.rafts.values(): race.update_mass(raft)
    race.scramble_result=scramble.result(routes)

func choose_early_swimmers() -> void:
    for tribe: Dictionary in configuration.tribes:
        var candidate := 0
        var best := 0.0
        for id_value in tribe.members:
            var id := int(id_value)
            if id==int(configuration.selected): continue
            var score := race.rating(id,"endurance")+race.rating(id,"speed")+race.rating(id,"balance")*.4+race.rating(id,"risk")*.7+race.rating(id,"awareness")*.3
            var variation := float((id*31+int(configuration.seed)*13)%19)*.22
            if score+variation>best:
                best=score+variation
                candidate=id
        # A swimmer is an attribute/seed decision, never a named or forced winner.
        if candidate!=0 and best>22.0 and (candidate+int(configuration.seed))%4!=0:
            race.actors[candidate].collect_until=3.0+float(candidate%5)
            race.actors[candidate].objective="early_swim"

func request_launch(actor: int) -> bool:
    if state!=State.ACTIVE or suspended or not race.actors.has(actor): return false
    var crew: Dictionary=race.actors[actor]
    if crew.raft.is_empty():
        race.feedback="Board your raft to encourage departure"
        return false
    var tribe: String=crew.tribe
    if race.rafts[tribe].state!="moored": return false
    launch_requests[tribe]=elapsed
    race.feedback="Departure requested; your crew is deciding"
    race.event("launch_encouraged",actor)
    return true

func evaluate_launches(access: Callable) -> void:
    var opponent_launches := 0
    for raft: Dictionary in race.rafts.values(): opponent_launches+=int(float(raft.launch_time)>=0)
    for tribe: Dictionary in configuration.tribes:
        var raft: Dictionary=race.rafts[tribe.id]
        if raft.state!="moored": continue
        var willing := 0
        var leadership := 0.0
        for id_value in raft.crew:
            var id := int(id_value)
            leadership=maxf(leadership,race.rating(id,"leader"))
            if race.actors[id].paddling: willing+=1
        var deadline := scramble.phase==MarooningScramble.Phase.SCRAMBLE_COMPLETE
        var encouraged := launch_requests.has(tribe.id)
        if willing<2 and deadline:
            for id_value in raft.crew:
                var id := int(id_value)
                if id!=int(configuration.selected) and not race.actors[id].paddling:
                    race.actors[id].paddling=true
                    willing+=1
                    if willing>=2: break
        var readiness := float(raft.crew.size())/maxf(1,float(raft.capacity))
        var urgency := elapsed+leadership*1.1+opponent_launches*7.0+(9.0 if encouraged else 0.0)
        var viable := willing>=mini(2,int(raft.capacity)) or (deadline and elapsed>=72 and willing>=1)
        var decide := viable and (deadline or (elapsed>=6 and readiness>=.5 and urgency>=27) or (encouraged and elapsed>=6 and urgency>=24))
        if not decide:
            raft.decision_at=-1.0
            continue
        if float(raft.decision_at)<0:
            raft.decision_at=elapsed+clampf(2.4-leadership*.12,1.2,2.3)
            continue
        if elapsed+.000001<float(raft.decision_at): continue
        var leader := int(raft.crew[0])
        if access.is_valid() and not bool(access.call(leader,"launch")):
            raft.launch_reason="Waiting for clear water"
            continue
        # No incomplete load can survive this atomic commitment.
        scramble.close_tribe(tribe.id,elapsed)
        var reason := "collection_closed" if deadline else ("crew_encouraged" if encouraged else "crew_ready")
        race.commit_launch(tribe.id,reason)

func wants_departure(actor: int) -> bool:
    var crew: Dictionary=race.actors[actor]
    return state==State.ACTIVE and (not scramble.eligible(actor) or scramble.phase==MarooningScramble.Phase.SCRAMBLE_COMPLETE or elapsed>=float(crew.collect_until))

func depart(actor: int, place: String) -> void:
    var crew: Dictionary=race.actors[actor]
    if crew.place=="deck" and place!="deck":
        scramble.release_on_deck(actor,crew.get("last_deck_position",crew.position),"departure")
        crew["left_deck_at"]=elapsed
        race.event("left_ship",actor)
    crew.place=place
    crew.mode="swimming" if place=="swimming" else ("walking" if place=="deck" else place)

func result() -> Dictionary:
    sync_cargo()
    var value := race.result()
    value.version=2
    value["implementation_sha"]=ProjectSettings.get_setting("marooning_build/implementation_sha","")
    value["clock_owner"]="marooning_session"
    value["collection_seconds"]=MarooningScramble.COLLECTION_SECONDS
    value["collection_closed"]=scramble.phase==MarooningScramble.Phase.SCRAMBLE_COMPLETE
    value["closed_stations"]=scramble.closed_tribes.duplicate(true)
    value["supply_rng_state"]=scramble.rng.state
    value["recoveries"]=recoveries.duplicate(true)
    value["session_state"]=state
    return value
