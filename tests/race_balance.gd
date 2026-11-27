extends "res://tests/race_test.gd"
## Deterministic authority harness, not a rendered/device playtest.
func scenario(count_value: int, cargo_kg: float, human: String, strength: float, swimmer_at: float, seed_value: int) -> Dictionary:
    var sim := fixture(count_value,seed_value)
    for actor: Dictionary in sim.actors.values():
        actor.attributes.strength = strength
    for raft: Dictionary in sim.rafts.values():
        raft.cargo_kg = cargo_kg
    board_all(sim)
    var left := false
    for frame in 24000:
        if human == "perfect" and absf(fmod(sim.elapsed,MarooningRace.BEAT)/MarooningRace.BEAT-.5) < .006:
            sim.stroke(1)
        if swimmer_at >= 0 and not left and sim.elapsed >= swimmer_at:
            sim.leave(1)
            left = true
        for id: int in sim.actors:
            var actor: Dictionary = sim.actors[id]
            if not actor.raft.is_empty() and sim.rafts[actor.tribe].arrived:
                sim.leave(id)
            if actor.raft.is_empty() and not sim.pending.has(id) and not actor.arrived:
                var prior: Vector3 = actor.position
                actor.position = prior.move_toward(sim.actor_objective(id),sim.swim_speed(id)/60)
                actor.swim_distance += prior.distance_to(actor.position)
        sim.advance(1.0/60)
        if sim.phase == MarooningRace.Phase.ARRIVAL_COMPLETE:
            break
    var rafts := {}
    for tribe: String in sim.rafts:
        var raft: Dictionary = sim.rafts[tribe]
        rafts[tribe] = {"cargo_kg":raft.cargo_kg,"peak_mass_kg":raft.peak_mass_kg,"max_speed":raft.max_speed,"arrival_time":raft.arrival_time,"crew_seconds":raft.crew_seconds,"paddler_seconds":raft.paddler_seconds}
    var strokes := 0
    var perfect := 0
    var swimmers := 0
    for actor: Dictionary in sim.actors.values():
        strokes += int(actor.strokes)
        perfect += int(actor.perfect)
        swimmers += int(int(actor.departures)>0)
    return {"tribes":count_value,"seed":seed_value,"cargo":cargo_kg,"human":human,"strength":strength,"swimmer_at":swimmer_at,"duration":sim.elapsed,"reward":sim.reward.tribe,"finished":sim.phase==MarooningRace.Phase.ARRIVAL_COMPLETE,"perfect_fraction":float(perfect)/maxf(1,strokes),"swimmers":swimmers,"rafts":rafts}
func _initialize() -> void:
    var rows: Array[Dictionary] = []
    for count_value in [2,3]:
        for parameters: Array in [[0,"misses",5,-1],[160,"misses",5,-1],[160,"perfect",5,-1],[160,"perfect",9,-1],[160,"misses",2,-1],[160,"perfect",5,30],[160,"perfect",5,65]]:
            rows.append(scenario(count_value,parameters[0],parameters[1],parameters[2],parameters[3],42))
    print("BALANCE_REPORT ",JSON.stringify(rows))
    for row: Dictionary in rows:
        check(row.finished,"Balanced scenario finishes")
    print("Balance: ",failures," failures")
    quit(1 if failures else 0)
