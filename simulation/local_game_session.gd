class_name LocalGameSession
extends GameSession

const MAX_STEPS := 4
var _simulation: SeasonSimulation
var _principal: String
var _physical_location := ""
var _talk_observation: Dictionary = {}
var _accumulator := 0.0
var last_step_usec := 0

func _init(simulation: SeasonSimulation, principal: String) -> void:
    _simulation = simulation
    _principal = principal

func submit(request: Dictionary) -> Dictionary:
    var result := _simulation.command(_principal, request, _talk_observation)
    _talk_observation = {}
    resolved.emit(result.duplicate(true))
    return result

func view(location: String) -> Dictionary:
    return _simulation.project(_principal, location)

func step(elapsed: float) -> void:
    var interval := SeasonSimulation.TICK_SECONDS
    _accumulator = minf(_accumulator + elapsed, interval * MAX_STEPS)
    if _accumulator < interval:
        return
    var started := Time.get_ticks_usec()
    while _accumulator >= interval:
        _simulation.advance(_physical_location)
        _accumulator -= interval
    last_step_usec = Time.get_ticks_usec() - started

func bind_physical_location(location: String) -> void:
    _physical_location = location
    _talk_observation = {}

func observe_talk(target: String, distance: float, accessible: bool) -> void:
    _talk_observation = {"location": _physical_location, "target": target,
        "distance": distance, "accessible": accessible}

func report_travel(id: String, activity: String, arrived: bool) -> bool:
    return _simulation.observe_travel(_physical_location, id, activity, arrived)

func checkpoint_pose(value: Dictionary) -> bool:
    if _physical_location != value.get("location") or _principal != _simulation.player_id or not GameStateData.pose(value):
        return false
    _simulation.pose = value.duplicate(true)
    _simulation.revision += 1
    return true

func checkpoint() -> Dictionary:
    return _simulation.snapshot() if _principal == _simulation.player_id else {}

func activity(location: String, id: String) -> Dictionary:
    # Hot path for local navigation. Returns only the projected activity fields.
    if _principal != _simulation.player_id or location != _physical_location:
        return {}
    var person: Dictionary = _simulation.camps[location].people[id]
    return {"activity": person.activity, "stage": person.stage}

func arrivals(location: String) -> int:
    return _simulation.camps[location].arrivals

func current_tick() -> int:
    return _simulation.tick

func current_day() -> int:
    return _simulation.day()
