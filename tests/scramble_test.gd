extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",message)
func fixture() -> MarooningScramble:
    var sim := MarooningScramble.new()
    var anchors: Array[Vector3] = []
    for i in 52:
        anchors.append(Vector3(i * 2,2,0))
    sim.configure({"seed":42,"tribes":[{"id":"a"},{"id":"b"}]},
        {1:{"position":Vector3(0,2,0),"tribe":"a","attributes":{}},2:{"position":Vector3(0,2,0),"tribe":"b","attributes":{}}},
        anchors,{"a":Vector3(0,2,0),"b":Vector3(6,2,0)},[Vector3(0,2,0)])
    sim.ready()
    sim.start()
    return sim
func _initialize() -> void:
    var sim := fixture()
    var second := fixture()
    check(sim.items == second.items,"Seeded placements repeat")
    var id: String = sim.items.keys()[0]
    sim.items[id].position = Vector3(0,2,0)
    check(sim.request(2,"pickup",id) and sim.request(1,"pickup",id),"Contested pickup accepts both arrivals")
    check(not sim.request(1,"pickup",id),"Repeated input cannot duplicate pending action")
    sim.advance(2)
    check(sim.carried(1) == id and sim.carried(2).is_empty(),"Equal completion resolves atomically by ID")
    check(sim.multiplier(1) < 1 and sim.multiplier(1) >= .45,"Carry modifier bounded")
    check(not sim.request(2,"load",id),"Rival cannot load owned cargo")
    check(sim.request(1,"drop",id),"Drop accepted")
    sim.advance(2)
    check(sim.items[id].state == MarooningScramble.State.DROPPED,"Drop releases ownership")
    sim.actors[1].position = Vector3(50,2,0)
    check(not sim.request(1,"pickup",id),"Remote pickup rejected")
    sim.actors[1].position = Vector3(0,2,0)
    check(not sim.request(1,"pickup",id,false),"Blocked access rejected")
    sim.request(1,"pickup",id)
    sim.advance(2)
    check(not sim.request(1,"throw",id),"Throw unavailable")
    check(sim.items[id].state == MarooningScramble.State.CARRIED and sim.result({}).secured.a.is_empty(),"Carried cargo never secured")
    sim.request(1,"drop",id)
    sim.advance(2)
    var next: String = sim.items.keys()[1]
    sim.items[next].position = Vector3(0,2,0)
    sim.request(1,"pickup",next)
    sim.advance(2)
    sim.request(1,"load",next)
    sim.advance(2)
    check(sim.result({}).secured.a.size() == 1,"Only successful loading secures cargo")
    sim.suspended = true
    var elapsed := sim.elapsed
    sim.advance(200)
    check(sim.elapsed == elapsed,"Suspension does not advance gameplay time")
    sim.suspended = false
    sim.advance(120)
    check(sim.phase == MarooningScramble.Phase.SCRAMBLE_COMPLETE and sim.items.size() == 50,"Expiry and conservation")
    check(not sim.request(1,"pickup",id),"Post-expiry commands rejected")
    var repeat_a := fixture()
    var repeat_b := fixture()
    for fixture_sim: MarooningScramble in [repeat_a,repeat_b]:
        var item_id: String = fixture_sim.items.keys()[0]
        fixture_sim.items[item_id].position = Vector3(0,2,0)
        fixture_sim.request(2,"pickup",item_id)
        fixture_sim.request(1,"pickup",item_id)
        fixture_sim.advance(2)
        fixture_sim.request(1,"load",item_id)
        fixture_sim.advance(2)
    check(repeat_a.items == repeat_b.items and repeat_a.events == repeat_b.events,"Seeded command fixtures repeat exactly")
    # Search bounded seed cases to prove both outcomes without changing ratings.
    var success_seed := -1
    var failure_seed := -1
    for seed_value in range(1,30):
        var theft := fixture()
        theft.rng.seed = seed_value
        var stolen: String = theft.items.keys()[0]
        theft.items[stolen].position = Vector3(0,2,0)
        theft.request(1,"pickup",stolen)
        theft.advance(2)
        theft.actors[2].position = Vector3(8,2,0)
        check(not theft.request(2,"steal",stolen),"Remote theft rejected")
        theft.actors[2].position = Vector3(0,2,0)
        check(not theft.request(2,"steal",stolen,false),"Occluded theft rejected")
        check(theft.request(2,"steal",stolen),"Theft takes a pending interaction")
        check(not theft.request(2,"steal",stolen),"Duplicate theft rejected")
        theft.advance(2)
        if theft.carried(2) == stolen:
            success_seed = seed_value
            check(theft.carried(1).is_empty(),"Success transfers exact instance")
            check(not theft.request(1,"steal",stolen),"Immediate revenge rejected")
        else:
            failure_seed = seed_value
            check(theft.carried(1)==stolen,"Failure preserves exact owner")
        check(not theft.request(2,"steal",stolen),"Theft cooldown bounded spam")
        check(theft.items.size()==50,"Theft conserves all instances")
        var terminal: Dictionary = theft.events.back()
        check(terminal.victim==1 and terminal.actor==2 and terminal.instance==stolen,"Semantic identities retained")
        theft.advance(120)
        check(not theft.request(2,"steal",stolen),"Expired theft rejected")
    check(success_seed>0 and failure_seed>0,"Seeded theft produces success and failure")
    var moving := fixture()
    var moving_id: String = moving.items.keys()[0]
    moving.items[moving_id].position = Vector3(0,2,0)
    moving.request(1,"pickup",moving_id)
    moving.advance(2)
    moving.request(2,"steal",moving_id)
    moving.actors[1].position = Vector3(10,2,0)
    moving.advance(2)
    check(moving.carried(1)==moving_id,"Theft completion revalidates range")
    moving.actors[1].position = Vector3(0,2,0)
    moving.request(1,"load",moving_id)
    moving.advance(2)
    check(not moving.request(2,"steal",moving_id),"Secured cargo cannot be stolen")
    var contests: Array[MarooningScramble] = []
    for reversed_order in [false,true]:
        var contest := fixture()
        contest.actors[3] = {"position":Vector3(0,2,0),"tribe":"b","attributes":{}}
        contest.contributions[3] = {}
        var cargo_id: String = contest.items.keys()[0]
        contest.items[cargo_id].position = Vector3(0,2,0)
        contest.request(1,"pickup",cargo_id)
        contest.advance(2)
        for thief: int in ([3,2] if reversed_order else [2,3]):
            contest.request(thief,"steal",cargo_id)
        contest.advance(2)
        var owners := 0
        for actor_id: int in contest.actors:
            owners += int(contest.carried(actor_id)==cargo_id)
        check(owners==1 and contest.items.size()==50,"Contested theft has one owner and conserves instances")
        contests.append(contest)
    check(contests[0].items==contests[1].items,"Contested theft completion is deterministic by actor ID")
    print("Scramble authority: ",failures," failures")
    quit(1 if failures else 0)
