extends SceneTree
var failures := 0
func check(value: bool,label: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",label)
func fixture() -> MarooningScramble:
    var sim := MarooningScramble.new()
    var points: Array[Vector3] = []
    for i in 50: points.append(Vector3(i*2,2,0))
    sim.configure({"seed":42,"tribes":[{"id":"a"},{"id":"b"}]},{1:{"position":Vector3(0,2,0),"tribe":"a","attributes":{}},2:{"position":Vector3(6,2,0),"tribe":"b","attributes":{}}},points,{"a":Vector3(0,2,0),"b":Vector3(6,2,0)},[])
    sim.ready()
    sim.start()
    sim.unloading = {"a":[Vector3(0,2,0),Vector3(0,2,2),Vector3(0,2,-2)],"b":[Vector3(6,2,0)]}
    var id: String = sim.items.keys()[0]
    sim.items[id].state = MarooningScramble.State.CARRIED
    sim.items[id].actor = 1
    return sim
func _initialize() -> void:
    var sim := fixture()
    var id := sim.carried(1)
    sim.advance(.01)
    check(sim.pending.has(1) and sim.carried(1)==id,"Deposit begins with visible handling, not instant award")
    check(not sim.request(1,"drop",id),"Pending deposit wins over later drop")
    sim.advance(2)
    check(sim.items[id].state==MarooningScramble.State.SECURED and sim.result({}).secured.a.size()==1,"Own area secures exact item once")
    sim.advance(2)
    check(sim.contributions[1].load_success==1,"Standing still cannot duplicate deposit")
    sim = fixture(); id = sim.carried(1)
    sim.actors[1].position = Vector3(6,2,0)
    sim.advance(2)
    check(sim.pending.is_empty() and sim.carried(1)==id,"Wrong tribe basket rejected")
    sim = fixture(); id = sim.carried(1)
    sim.advance(.01,func(_a: int,_b: String,_c: String) -> bool: return false)
    check(sim.pending.is_empty(),"Wall blocks initiation")
    sim.advance(.01)
    sim.advance(2,func(_a: int,_b: String,_c: String) -> bool: return false)
    check(sim.carried(1)==id,"Wall revalidated at completion")
    sim = fixture(); id = sim.carried(1)
    sim.advance(.01)
    sim.actors[1].position = Vector3(30,2,0)
    sim.advance(2)
    check(sim.carried(1)==id,"Moving away cancels deposit")
    sim = fixture(); id = sim.carried(1)
    sim.elapsed = 119.9
    sim.advance(.1)
    sim.advance(2)
    check(sim.carried(1)==id and sim.pending.is_empty(),"Expiry never awards unfinished cargo")
    sim = fixture(); id = sim.carried(1)
    sim.actors[1].position = Vector3(0,2,2.7)
    sim.advance(2)
    check(sim.items[id].state==MarooningScramble.State.SECURED,"Alternative unloading position works")
    sim = fixture(); id = sim.carried(1)
    sim.cooldowns[1] = sim.elapsed+5
    sim.advance(2)
    check(sim.items[id].state==MarooningScramble.State.SECURED,"Theft cooldown never locks ordinary deposit")
    sim = fixture(); id = sim.carried(1)
    sim.cooldowns[1] = sim.elapsed+5
    sim.actors[1].position = Vector3(0,2,5)
    check(sim.request(1,"drop",id),"Theft cooldown never locks ordinary drop")
    print("Automatic deposit: ",failures," failures")
    quit(1 if failures else 0)
