extends "res://tests/session_test.gd"

func isolated() -> MarooningRace:
    var session := fixture()
    var sim := session.race
    sim.active=true
    sim.reward_position=Vector3(0,0,1000)
    sim.reward_deadline=INF
    for id in [1,2]:
        sim.actors[id].position=sim.to_world('t0',MarooningRace.access_points()[id-1])
        check(sim.request_board(id),"Controlled crew boards through reservations")
    for i in 240: sim.advance(MarooningRace.STEP)
    check(sim.commit_launch('t0','controlled_trial'),"Controlled crew launches")
    sim.set_rest(2,true)
    sim.rafts.t0.strategy_at=INF
    return sim

func trial(phase_value: float, quality: float, grade: String) -> Dictionary:
    var sim := isolated()
    sim.elapsed=MarooningRace.BEAT*(4+phase_value)
    sim.apply_stroke(1,quality,grade)
    var impulse: float=sim.actors[1].impulse_total_ns
    for i in 240: sim.advance(MarooningRace.STEP)
    check(absf(float(sim.actors[1].impulse_delivered_ns)-impulse)<.00001,"Full stroke impulse survives a beat boundary")
    return {"distance":sim.rafts.t0.distance,"impulse":impulse,"delivered":sim.actors[1].impulse_delivered_ns}

func _initialize() -> void:
    var perfect := trial(.5,1.5,'Perfect')
    var good := trial(.4,1.1,'Good')
    var early := trial(.02,.65,'Early/Late')
    var late := trial(.98,.65,'Early/Late')
    check(perfect.impulse>good.impulse and good.impulse>early.impulse,"Equal-state accepted impulse Perfect > Good > Mistimed")
    check(perfect.distance>good.distance and good.distance>early.distance,"Equal-state physical distance Perfect > Good > Mistimed")
    check(absf(float(early.distance)-float(late.distance))<.00001,"Early and late mistimed input deliver equal impulse and distance")
    var sim := isolated()
    sim.elapsed=MarooningRace.BEAT*4.5
    check(sim.stroke(1)=='Perfect' and sim.stroke(1)=='',"One accepted input per cycle, including repeat/held input")
    sim.advance(MarooningRace.STEP)
    check(sim.rafts.t0.velocity.length()>0 and sim.rafts.t0.distance>0,"First accepted stroke changes actual displacement in one fixed step")
    var before: float=sim.actors[1].impulse_delivered_ns
    var now: float=sim.elapsed
    sim.suspended=true
    sim.advance(10)
    check(sim.elapsed==now and sim.actors[1].impulse_delivered_ns==before,"Suspension preserves the live impulse without background misses")
    sim.suspended=false
    sim.set_rest(1,true)
    check(sim.actors[1].live_strokes.is_empty() and sim.actors[1].power==0,"Rest cancels remaining contribution")
    check(absf(float(sim.actors[1].impulse_total_ns)-float(sim.actors[1].impulse_delivered_ns)-float(sim.actors[1].impulse_cancelled_ns))<.00001,"Accepted impulse is delivered or explicitly cancelled, never duplicated")
    # A measurable controlled initial momentum, rather than a sub-millimetre
    # first-step displacement rounded by Vector3's float storage.
    sim.rafts.t0.momentum=1.5
    sim.rafts.t0.speed=1.5
    var coasting: float=sim.rafts.t0.speed
    for frame in 120: sim.advance(MarooningRace.STEP)
    check(sim.rafts.t0.speed<coasting,"No contributing paddlers produces drag-only coasting")
    var blocked := isolated()
    blocked.elapsed=MarooningRace.BEAT*4.5
    blocked.stroke(1)
    for frame in 60: blocked.advance(MarooningRace.STEP,func(_id: int,action: String) -> bool: return action!='vessel')
    check(blocked.rafts.t0.distance==0 and blocked.rafts.t0.velocity==Vector3.ZERO and blocked.rafts.t0.max_speed==0,"Blocked planned travel earns no distance or fictitious speed")
    var light := isolated()
    var heavy := isolated()
    heavy.rafts.t0.cargo_kg=160.0
    for current: MarooningRace in [light,heavy]:
        current.elapsed=MarooningRace.BEAT*4.5
        current.stroke(1)
        current.advance(MarooningRace.STEP)
    check(light.rafts.t0.speed>heavy.rafts.t0.speed and heavy.rafts.t0.draft>light.rafts.t0.draft,"Real extra kg lowers acceleration and increases draft")
    var moored := fixture().race
    moored.active=true
    moored.actors[1].position=moored.boarding_point('t0')
    moored.request_board(1)
    for i in 240: moored.advance(MarooningRace.STEP)
    check(moored.stroke(1)=='' and moored.actors[1].live_strokes.is_empty(),"Moored input receives honest rejection, no hidden force")
    print('IMPULSE_REPORT ',JSON.stringify({"perfect":perfect,"good":good,"early":early,"late":late}))
    print('Stroke impulses: ',failures,' failures')
    quit(1 if failures else 0)
