extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL: ",message)

func fixture(count_value := 2, seed_value := 42) -> MarooningSession:
    var roster := {}
    var tribes: Array=[]
    var stations := {}
    var routes := {}
    var anchors: Array[Vector3]=[]
    for i in 50: anchors.append(Vector3(i*2,2,0))
    for t in count_value:
        var tribe := "t%d"%t
        var members: Array=[]
        for index in 18/count_value:
            var id := t*(18/count_value)+index+1
            members.append(id)
            roster[id]={"tribe":tribe,"position":Vector3(t*30,2,0),"attributes":{"strength":5,"dexterity":5,"endurance":5,"speed":5,"risk":5,"leader":5,"laziness":5}}
        tribes.append({"id":tribe,"members":members,"name":"Fixture %d"%t,"color":"orange"})
        stations[tribe]=Vector3(t*30,2,0)
        routes[tribe]={"raft_id":tribe,"raft_mount":Vector3(t*30,0,10),"heading":0,"destination":Vector3(t*30,0,180),"shore_center":Vector3(t*30,0,172),"stop_position":Vector3(t*30,0,158),"route_id":"shore-%d"%t}
    var sim := MarooningSession.new()
    sim.configure({"seed":seed_value,"selected":1,"catalog":"technical-fixture","tribes":tribes},roster,anchors,stations,[],routes,Vector3(15,0,100))
    return sim

func run_seconds(sim: MarooningSession, seconds: float) -> void:
    for frame in int(round(seconds/MarooningRace.STEP)): sim.advance(MarooningRace.STEP)

func held(sim: MarooningSession, id: int, item_id: String) -> void:
    sim.scramble.items[item_id].state=MarooningScramble.State.CARRIED
    sim.scramble.items[item_id].actor=id
    sim.race.actors[id].position=sim.scramble.stations[sim.race.actors[id].tribe]
    sim.race.actors[id].last_deck_position=sim.race.actors[id].position

func _initialize() -> void:
    var sim := fixture()
    sim.advance(10)
    check(sim.elapsed==0 and sim.race.elapsed==0,"Intro has no gameplay time")
    sim.ready()
    sim.start(false)
    sim.scramble.actors[1].fatigue=.2
    check(sim.race.actors[1].fatigue==.2,"Travel and supplies share the same canonical actor")
    held(sim,1,"rice-00")
    check(sim.scramble.request(1,"load","rice-00"),"Validated prelaunch deposit begins")
    run_seconds(sim,2)
    check(sim.scramble.items['rice-00'].state==MarooningScramble.State.SECURED,"Deposit commits exact item before any launch")
    for id in range(1,6):
        sim.race.actors[id].position=sim.race.to_world('t0',MarooningRace.access_points()[id-1])
        check(sim.race.request_board(id),"Own moored access reserves a climb")
    run_seconds(sim,4)
    sim.race.actors[6].position=sim.race.boarding_point('t0')
    check(sim.race.request_board(6),"Released access can take the next climber")
    run_seconds(sim,4)
    check(sim.race.rafts.t0.crew.size()==6,"Reserved climbs seat crew once")
    check(sim.race.rafts.t0.state=='moored',"No unconditional race-wide assembly launch")
    check(sim.request_launch(1),"Aboard contestant may encourage departure")
    for frame in 600:
        sim.advance(MarooningRace.STEP)
        if sim.race.rafts.t0.decision_at>=0: break
    var decision: float=sim.race.rafts.t0.decision_at
    while sim.elapsed<decision-.05: sim.advance(MarooningRace.STEP)
    held(sim,8,'water-00')
    check(sim.scramble.request(8,'load','water-00'),"Load may start before commitment")
    run_seconds(sim,3)
    check(sim.race.rafts.t0.state=='underway' and sim.scramble.closed_tribes.has('t0'),"Independent launch locks only that station")
    check(sim.scramble.items['water-00'].state==MarooningScramble.State.DROPPED,"Incomplete launch-time load is released, not awarded")
    check(not sim.scramble.request(8,'pickup','water-00'),"Departed tribe cannot resume ship collection")
    held(sim,10,'rice-01')
    check(sim.scramble.request(10,'load','rice-01'),"Other moored tribe remains eligible")
    run_seconds(sim,2)
    check(sim.scramble.items['rice-01'].state==MarooningScramble.State.SECURED,"Other tribe's concurrent deposit completes")
    var at: float=sim.elapsed
    sim.set_suspended(true)
    sim.advance(5)
    check(sim.elapsed==at and sim.race.elapsed==at,"One clock and authority freeze on suspension")
    sim.set_suspended(false)
    while sim.elapsed<58: sim.advance(MarooningRace.STEP)
    held(sim,10,'pot-00')
    sim.scramble.request(10,'load','pot-00')
    sim.scramble.pending[10].at=60.0
    held(sim,11,'pot-01')
    sim.scramble.request(11,'load','pot-01')
    sim.scramble.pending[11].at=60.001
    while sim.elapsed<60.01: sim.advance(MarooningRace.STEP)
    check(sim.scramble.items['pot-00'].state==MarooningScramble.State.SECURED,"Exact 60s completion precedes deadline closure")
    check(sim.scramble.items['pot-01'].state!=MarooningScramble.State.SECURED,"Incomplete deadline action is never awarded")
    check(sim.scramble.phase==MarooningScramble.Phase.SCRAMBLE_COMPLETE,"Collection closes at sixty seconds")
    check(sim.elapsed==sim.race.elapsed and sim.scramble.elapsed==sim.elapsed,"Derived collection clock remains the single gameplay clock")
    var handoff := sim.result()
    var count: int=handoff.scramble.unsecured.size()
    for rows: Array in handoff.scramble.secured.values(): count+=rows.size()
    check(count==50 and handoff.version==2 and handoff.configuration==sim.configuration,"v2 handoff conserves fifty dispositions and original configuration")
    var swimmer := fixture(3)
    swimmer.ready()
    swimmer.start(false)
    swimmer.race.actors[1].place='swimming'
    swimmer.race.actors[1].position=swimmer.race.reward_position
    check(swimmer.race.claim(1) and not swimmer.race.claim(2),"Early swimmer can claim exactly once while all rafts are moored")
    check(swimmer.race.reward.location=='carried' and swimmer.race.rafts.t0.cargo_kg==0,"Swimmer reward is not mass on a distant raft")
    check(swimmer.scramble.eligible(7),"Reward resolution does not close another tribe's station")
    var no_reward := fixture()
    no_reward.ready()
    no_reward.start(false)
    no_reward.race.reward_deadline=2
    run_seconds(no_reward,3)
    check(no_reward.race.reward.status=='unclaimed' and no_reward.race.reward.tribe=='',"No-reward timeout redirects without inventing a winner")
    print('Concurrent session: ',failures,' failures')
    quit(1 if failures else 0)
