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
    sim.request(1,"throw",id)
    sim.advance(2)
    check(sim.items[id].state == MarooningScramble.State.FLOATING and sim.result({}).secured.a.is_empty(),"Floating cargo never secured")
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
    print("Scramble authority: ",failures," failures")
    quit(1 if failures else 0)
