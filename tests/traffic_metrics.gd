extends RefCounted
## Matched sampling for old/new scenes, without altering decisions or movement.
var positions := {}
var headings := {}
var jams := {}
var episodes: Array[Dictionary]=[]
var reversals := {}
var peak_station_capsules := 0
var peak_reserved_approaches := 0
var last_elapsed := 0.0
func sample(preview: Node, simulation: RefCounted, elapsed: float) -> void:
    var adapter: Node=preview.get("scramble")
    var agents: Dictionary=adapter.get("agents")
    var cast: Dictionary=preview.get("cast")
    var traffic: RefCounted=adapter.get("traffic")
    var pending: Dictionary=simulation.get("pending")
    var slots: Dictionary=traffic.get("slots")
    last_elapsed=elapsed
    for id: int in agents:
        var actor: CampHumanoidMotor=cast[id]
        var held: String=simulation.call("carried",id)
        var active_carrier := not held.is_empty() and not pending.has(id) and slots.has(id)
        var still := positions.has(id) and MarooningDeckTraffic.planar(positions[id],actor.position)<.1
        var previous := float(jams.get(id,0))
        jams[id]=previous+1.0 if active_carrier and still else 0.0
        if previous>0 and float(jams[id])==0:
            episodes.append({"actor":id,"seconds":previous,"ended":elapsed})
        positions[id]=actor.position
        # The matched comparison window is60s. Full90s carrier gates stay unchanged.
        if elapsed<=60.001:
            var speed := Vector2(actor.get_real_velocity().x,actor.get_real_velocity().z).length()
            if headings.has(id) and speed<.1 and absf(angle_difference(float(headings[id]),actor.travel_heading))>PI/2:
                reversals[id]=int(reversals.get(id,0))+1
            headings[id]=actor.travel_heading
    if elapsed<=60.001:
        peak_reserved_approaches=maxi(peak_reserved_approaches,slots.size())
        var approaches: Dictionary=simulation.get("unloading")
        for rows: Array in approaches.values():
            for point: Vector3 in rows:
                var near := 0
                for actor: CampPhysicalMotor in cast.values():
                    if absf(actor.position.y-point.y)<.65 and MarooningDeckTraffic.planar(actor.position,point)<.75: near+=1
                peak_station_capsules=maxi(peak_station_capsules,near)
func result() -> Dictionary:
    var rows := episodes.duplicate(true)
    for id: int in jams:
        if float(jams[id])>0: rows.append({"actor":id,"seconds":jams[id],"ended":last_elapsed})
    var durations: Array[float]=[]
    for row: Dictionary in rows: durations.append(float(row.seconds))
    durations.sort()
    var worst_reversals := 0
    for value in reversals.values(): worst_reversals=maxi(worst_reversals,int(value))
    return {"matched_window_seconds":60,"sample_interval_seconds":1,"stationary_heading_reversals":reversals,"worst_reversals":worst_reversals,"peak_capsules_within_075m_of_approach":peak_station_capsules,"peak_reserved_approaches":peak_reserved_approaches,"carrier_stall_episodes":rows,"percentile_method":"nearest_rank","stall_p50":percentile(durations,.5),"stall_p95":percentile(durations,.95),"stall_max":durations.back() if not durations.is_empty() else 0.0}
func percentile(sorted_values: Array[float], fraction: float) -> float:
    return sorted_values[maxi(0,ceili(sorted_values.size()*fraction)-1)] if not sorted_values.is_empty() else 0.0
