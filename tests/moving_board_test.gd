extends "res://tests/stroke_impulse_test.gd"
func _initialize() -> void:
    var sim := isolated()
    check(sim.leave(1),"Jump releases a seated contestant")
    sim.rafts.t0.momentum=3.8
    sim.rafts.t0.speed=3.8
    sim.rafts.t0.velocity=Vector3(0,0,3.8)
    var start: Vector3=sim.actors[1].position
    check(sim.request_board(1),"Own side access accepts a reachable moving climb")
    var access_index: int=sim.pending[1].access
    for frame in 240: sim.advance(MarooningRace.STEP)
    check(sim.actors[1].raft=='t0' and sim.actors[1].boardings==2,"Reserved moving climb completes despite world-space movement")
    check((sim.actors[1].position as Vector3).distance_to(start)>2.7,"The vessel actually moved beyond the old world-point completion range")
    check(sim.rafts.t0.crew.count(1)==1 and sim.pending.is_empty(),"No duplicate crew or stale climb reservation")
    check((sim.actors[1].position as Vector3).distance_to(sim.to_world('t0',MarooningRace.seat(0)))<.0001,"Seated attachment has no cumulative platform drift")
    sim.leave(1)
    check(sim.request_board(1),"A later legitimate reboard remains available")
    sim.advance(.2)
    sim.suspended=true
    sim.cancel_climbs('focus')
    var frozen: Vector3=sim.actors[1].position
    sim.advance(1)
    check(sim.pending.is_empty() and sim.actors[1].raft=='' and sim.actors[1].position==frozen,"Focus cancels the climb and freezes its physical ownership")
    sim.suspended=false
    sim.actors[1].position=sim.to_world('t0',MarooningRace.access_points()[access_index])
    check(not sim.request_board(1,false),"Intervening geometry rejects initiation")
    sim.actors[1].velocity=Vector3(0,0,-10)
    check(not sim.request_board(1),"Unsafe relative speed rejects a remote capture")
    sim.actors[1].velocity=Vector3.ZERO
    check(sim.request_board(1),"Safe in-range retry reserves its own access")
    for frame in 240: sim.advance(MarooningRace.STEP,func(_id: int,action: String) -> bool: return action!='climb')
    check(sim.actors[1].raft=='' and sim.pending.is_empty(),"Completion revalidates safety and cancels cleanly")
    sim.actors[1].position=sim.boarding_point('t1')
    check(not sim.request_board(1),"Another tribe's nearby vessel cannot capture the contestant")
    print('Moving boarding: ',failures,' failures')
    quit(1 if failures else 0)
