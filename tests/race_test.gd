extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",message)
func fixture(count_value := 2, seed_value := 42) -> MarooningRace:
    var roster := {}
    var config := {"seed":seed_value,"selected":1,"tribes":[]}
    var cargo := {"secured":{}}
    var routes := {}
    for t in count_value:
        var tribe := "t%d" % t
        var members: Array[int] = []
        for i in 18/count_value:
            var id := t*(18/count_value)+i+1
            members.append(id)
            roster[id] = {"tribe":tribe,"position":Vector3(t*10,0,4),"attributes":{"strength":5,"endurance":5,"dexterity":5,"speed":5,"balance":5,"laziness":5,"risk":5,"awareness":5}}
        config.tribes.append({"id":tribe,"members":members})
        cargo.secured[tribe] = []
        routes[tribe] = {"raft_id":tribe,"raft_mount":Vector3(t*10,0,0),"destination":Vector3(t*20,0,180),"route_id":tribe}
    var sim := MarooningRace.new()
    sim.configure(config,roster,cargo,routes,Vector3(5,0,100))
    return sim
func board_all(sim: MarooningRace) -> void:
    var remaining := sim.actors.keys()
    # Real concurrent access reservations, followed by a second capacity wave.
    while not remaining.is_empty():
        for id: int in remaining.duplicate():
            var index := sim.nearest_access(id,true)
            if index<0: continue
            sim.actors[id].position=sim.to_world(sim.actors[id].tribe,MarooningRace.access_points()[index])
            if sim.request_board(id): remaining.erase(id)
        for frame in 300: sim.advance(1.0/60)
    for tribe: String in sim.rafts: check(sim.commit_launch(tribe,"authority_fixture"),"Crew launches independently")
func run_race(count_value: int, seed_value: int) -> Dictionary:
    var sim := fixture(count_value,seed_value)
    board_all(sim)
    for frame in 24000:
        # Technical physical-position harness: integrate independent swimmers.
        for id: int in sim.actors:
            var actor: Dictionary = sim.actors[id]
            if not actor.raft.is_empty() and sim.rafts[actor.tribe].arrived:
                sim.leave(id)
            if actor.raft.is_empty() and not sim.pending.has(id) and not actor.arrived:
                var goal := sim.actor_objective(id)
                actor.position = actor.position.move_toward(goal,sim.swim_speed(id)/60)
        sim.advance(1.0/60)
        if sim.phase == MarooningRace.Phase.ARRIVAL_COMPLETE:
            break
    check(sim.phase == MarooningRace.Phase.ARRIVAL_COMPLETE,"Autonomous race finishes")
    check(not sim.reward.tribe.is_empty(),"Reward claimed")
    return sim.result()
func _initialize() -> void:
    var sim := fixture()
    check(not sim.request_board(1,false),"Blocked boarding rejected")
    sim.actors[1].position=Vector3(100,0,0)
    check(not sim.request_board(1),"Remote boarding rejected")
    sim.actors[1].position=sim.boarding_point("t0")
    check(sim.request_board(1),"Climb begins")
    for i in 240: sim.advance(1.0/60)
    check(sim.actors[1].raft=="t0","Reserved local anchor completes without obsolete world-point recheck")
    sim=fixture()
    board_all(sim)
    check(sim.rafts.t0.crew.size()==9,"Nine seats occupied")
    for a: int in sim.rafts.t0.crew:
        for b: int in sim.rafts.t0.crew:
            if a!=b: check(sim.actors[a].position.distance_to(sim.actors[b].position)>.72,"Unique nonoverlapping occupied anchors")
    var positions := {}
    for i in 9: positions[MarooningRace.seat(i)]=true
    check(positions.size()==9,"Unique nine-person anchors")
    sim.update_mass(sim.rafts.t0)
    var mass: float=sim.rafts.t0.mass_kg
    var draft: float=sim.rafts.t0.draft
    sim.rafts.t0.cargo_kg+=100
    sim.update_mass(sim.rafts.t0)
    check(sim.rafts.t0.draft>draft,"Cargo increases displacement")
    check(sim.leave(1),"Jump removes member")
    check(sim.rafts.t0.mass_kg==mass+25,"Jump removes75kg immediately")
    check(sim.actors[1].power==0 and not sim.rafts.t0.crew.has(1),"Jump removes force/membership")
    sim.suspended=true
    var clock := sim.elapsed
    sim.advance(100)
    check(sim.elapsed==clock,"Focus pause preserves time")
    sim.suspended=false
    sim.actors[2].beat=-100
    sim.actors[2].stroke_at=-10
    check(not sim.stroke(2).is_empty() and sim.stroke(2).is_empty(),"Stroke spam rejected")
    sim.actors[1].position=sim.reward_position
    check(sim.claim(1) and not sim.claim(2),"Reward exclusive")
    var fatigue := fixture()
    fatigue.apply_stroke(1,1.1,"Good")
    var fresh: float=fatigue.actors[1].live_strokes[0].impulse
    fatigue.actors[1].fatigue=1
    fatigue.apply_stroke(1,1.1,"Good")
    check(fatigue.actors[1].live_strokes[1].impulse<fresh,"Fatigue lowers accepted impulse")
    var strategic := fixture()
    board_all(strategic)
    strategic.rafts.t0.speed=.4
    for id: int in strategic.rafts.t0.crew:
        strategic.actors[id].position=strategic.reward_position-Vector3(0,0,12)
        strategic.actors[id].attributes.risk=10
        strategic.actors[id].attributes.awareness=10
    strategic.strategy("t0")
    check(strategic.rafts.t0.crew.size()==8,"At most one strategic swimmer per decision")
    var moving := fixture()
    board_all(moving)
    moving.leave(1)
    moving.actors[1].position=moving.boarding_point("t0")
    moving.actors[1].velocity=moving.rafts.t0.velocity
    check(moving.request_board(1),"Moving reboard begins")
    for frame in 300: moving.advance(1.0/60)
    check(moving.actors[1].raft=="t0" and moving.rafts.t0.crew.count(1)==1,"Moving reboard completes exactly once")
    check(moving.actors[1].position.distance_to(moving.to_world("t0",MarooningRace.seat(0)))<.00001,"No cumulative anchor drift")
    var results: Array=[]
    for count_value in [2,3]:
        for seed_value in [1,42,99]:
            var result := run_race(count_value,seed_value)
            var stats := {}
            for tribe: String in result.rafts:
                var raft: Dictionary=result.rafts[tribe]
                stats[tribe]={"cargo_kg":raft.cargo_kg,"mass_kg":raft.mass_kg,"max_speed":raft.max_speed,"arrival_time":raft.arrival_time}
            results.append({"tribes":count_value,"seed":seed_value,"duration":result.elapsed,"reward":result.reward.tribe,"rafts":stats})
    print("BALANCE ",JSON.stringify(results))
    print("Race authority: ",failures," failures")
    quit(1 if failures else 0)
