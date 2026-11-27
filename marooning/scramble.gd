class_name MarooningScramble
extends RefCounted
## Scene-independent authority. Adapter supplies collision-validated positions/access.
## No reservation owns an item. Completion order, then contestant ID breaks ties.
enum Phase { INTRODUCTION, READY, SCRAMBLE_ACTIVE, SCRAMBLE_COMPLETE }
enum State { ABOARD, CARRIED, DROPPED, FLOATING, SECURED, ABANDONED }
var phase := Phase.INTRODUCTION
var duration := 120.0
var elapsed := 0.0
var tick := 0
var configuration: Dictionary
var definitions := MarooningSupplyCatalog.definitions()
var items: Dictionary = {}
var actors: Dictionary = {}
var stations: Dictionary = {}
var openings: Array[Vector3] = []
var unloading: Dictionary = {} # Optional physical approach positions; legacy station contract retained.
var pending: Dictionary = {}
var events: Array[Dictionary] = []
var suspended := false
var seed_value := 1
var rng := RandomNumberGenerator.new()
var cooldowns: Dictionary = {}
var contributions: Dictionary = {}

func configure(config: Dictionary, roster: Dictionary, anchors: Array[Vector3], loading: Dictionary, access: Array[Vector3]) -> void:
    configuration = config.duplicate(true)
    seed_value = int(config.get("seed", 1))
    actors = roster.duplicate(true)
    for actor: int in actors:
        contributions[actor] = {}
    stations = loading.duplicate(true)
    openings = access.duplicate()
    rng.seed = seed_value
    var slots := anchors.duplicate()
    # Fisher-Yates; global RNG and rendering never influence cargo placement.
    for i in range(slots.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var old: Vector3 = slots[i]
        slots[i] = slots[j]
        slots[j] = old
    for type: String in definitions:
        for index in int(definitions[type].count):
            var id := "%s-%02d" % [type,index]
            items[id] = {"id":id,"type":type,"state":State.ABOARD,"actor":0,"tribe":"", "position":slots[items.size()]}

func ready() -> void:
    phase = Phase.READY

func start() -> void:
    if phase == Phase.READY:
        phase = Phase.SCRAMBLE_ACTIVE

func carried(actor: int) -> String:
    for id: String in items:
        if items[id].state == State.CARRIED and items[id].actor == actor:
            return id
    return ""

func multiplier(actor: int) -> float:
    var id := carried(actor)
    if id.is_empty():
        return 1.0
    return clampf(float(definitions[items[id].type].speed) + (rating(actor,"strength") - 5) * .012, .45, .99)

func rating(actor: int, key: String) -> float:
    return clampf(float(actors[actor].attributes.get(key, 5)), 1, 10)

func request(actor: int, action: String, id: String, accessible := true) -> bool:
    if phase != Phase.SCRAMBLE_ACTIVE or suspended or pending.has(actor) or not actors.has(actor) or not items.has(id) or not accessible:
        return false
    if action == "throw" or (action=="steal" and float(cooldowns.get(actor,0))>elapsed):
        return false
    if not valid(actor, action, id):
        return false
    var definition: Dictionary = definitions[items[id].type]
    var seconds: float = .8 if action == "steal" else (definition.loading_duration if action == "load" else definition.pickup_duration)
    pending[actor] = {"action":action,"item":id,"started":elapsed,"at":elapsed + seconds * clampf(1.15 - rating(actor,"dexterity") * .03,.8,1.12)}
    pending[actor]["victim"] = int(items[id].actor) if action == "steal" else 0
    if action == "steal":
        cooldowns[actor] = elapsed + 5
        record(actor,id,action,"attempted",int(items[id].actor))
    return true

func valid(actor: int, action: String, id: String) -> bool:
    var item: Dictionary = items[id]
    var point: Vector3 = actors[actor].position
    if action == "steal":
        var victim := int(item.actor)
        return (pending.has(actor) or float(cooldowns.get(actor,0))<=elapsed) and carried(actor).is_empty() and item.state == State.CARRIED and victim != actor and actors.has(victim) and point.distance_to(actors[victim].position) <= (2.15 if pending.has(actor) else 1.95) and float(cooldowns.get(victim,0)) <= elapsed
    if action == "pickup":
        return carried(actor).is_empty() and item.state in [State.ABOARD,State.DROPPED] and point.distance_to(item.position) <= (1.9 if pending.has(actor) else 1.75)
    if item.state != State.CARRIED or item.actor != actor:
        return false
    if action == "drop":
        return true
    if action == "load":
        return in_unloading_area(actor)
    return false

func in_unloading_area(actor: int) -> bool:
    var point: Vector3 = actors[actor].position
    var tribe: String = actors[actor].tribe
    for slot: Vector3 in unloading.get(tribe,[stations[tribe]]):
        if absf(point.y-slot.y) < .65 and Vector2(point.x-slot.x,point.z-slot.z).length() <= (1.05 if unloading.has(tribe) else 1.45):
            return true
    return false

func auto_deposit(access_check: Callable) -> void:
    if unloading.is_empty(): return # Legacy callers explicitly load; physical scenes install zones.
    # Existing in-progress commands win; a later Drop cannot replace a locked load.
    # Sorted actors and the ordinary command processor preserve deterministic ties.
    var ids := actors.keys()
    ids.sort()
    for actor: int in ids:
        var held := carried(actor)
        if held.is_empty() or pending.has(actor) or not in_unloading_area(actor):
            continue
        var clear := not access_check.is_valid() or bool(access_check.call(actor,"load",held))
        request(actor,"load",held,clear)

func advance(delta: float, access_check: Callable = Callable()) -> void:
    if phase != Phase.SCRAMBLE_ACTIVE or suspended:
        return
    auto_deposit(access_check)
    elapsed = minf(elapsed + maxf(delta,0), duration)
    tick += 1
    var order := pending.keys()
    order.sort_custom(func(a: int,b: int) -> bool: return pending[a].at < pending[b].at if pending[a].at != pending[b].at else a < b)
    for actor: int in order:
        var command: Dictionary = pending[actor]
        # Expiry cancels unfinished actions; completions at exactly duration count.
        if command.at > elapsed:
            continue
        var id: String = command.item
        var action: String = command.action
        var allowed := valid(actor,action,id)
        if access_check.is_valid():
            allowed = allowed and access_check.call(actor,action,id)
        var victim := int(command.get("victim",0))
        if action == "steal":
            allowed = allowed and items[id].actor == victim
            if allowed:
                var chance := clampf(.5 + (rating(actor,"dexterity") + rating(actor,"deception") - rating(victim,"awareness") - rating(victim,"dexterity")) * .035,.15,.85)
                allowed = rng.randf() < chance
            cooldowns[actor] = elapsed + 5
            if allowed:
                cooldowns[victim] = elapsed + 4
        if allowed:
            var item: Dictionary = items[id]
            item.position = actors[actor].position
            match action:
                "pickup":
                    item.state = State.CARRIED
                    item.actor = actor
                "steal":
                    item.actor = actor
                "drop":
                    item.state = State.DROPPED
                    item.actor = 0
                "load":
                    item.state = State.SECURED
                    item.tribe = actors[actor].tribe
                    item.actor = 0
            items[id] = item
        record(actor,id,action,"success" if allowed else "failed",victim)
        pending.erase(actor)
    if elapsed >= duration:
        for actor: int in pending:
            record(actor,pending[actor].item,pending[actor].action,"expired")
        pending.clear()
        phase = Phase.SCRAMBLE_COMPLETE

func record(actor: int, id: String, action: String, outcome: String, victim := 0) -> void:
    var key := action + "_" + outcome
    contributions[actor][key] = int(contributions[actor].get(key,0)) + 1
    var witnesses: Array[int] = []
    for other: int in actors:
        if other != actor and actors[other].position.distance_to(actors[actor].position) < 6:
            witnesses.append(other)
    events.append({"tick":tick,"elapsed":elapsed,"actor":actor,"tribe":actors[actor].tribe,
        "victim":victim,"victim_tribe":actors[victim].tribe if actors.has(victim) else "",
        "against_tribemate":actors.has(victim) and actors[victim].tribe == actors[actor].tribe,
        "instance":id,"type":items[id].type,"action":action,"outcome":outcome,"nearby_witnesses":witnesses})
    if events.size() > 512:
        events.pop_front()

func result(routes: Dictionary) -> Dictionary:
    var secured := {}
    for tribe: Dictionary in configuration.tribes:
        secured[tribe.id] = []
    var unsecured: Array[Dictionary] = []
    for item: Dictionary in items.values():
        if item.state == State.SECURED:
            secured[item.tribe].append(item.duplicate(true))
        else:
            var row := item.duplicate(true)
            if row.state == State.CARRIED:
                row.position = actors[row.actor].position
            unsecured.append(row)
    var floating: Array[Dictionary] = []
    var carried_cargo: Array[Dictionary] = []
    var dropped: Array[Dictionary] = []
    var abandoned: Array[Dictionary] = []
    for row: Dictionary in unsecured:
        match row.state:
            State.FLOATING: floating.append(row.duplicate(true))
            State.CARRIED: carried_cargo.append(row.duplicate(true))
            State.DROPPED: dropped.append(row.duplicate(true))
            _: abandoned.append(row.duplicate(true))
    return {"contributions":contributions.duplicate(true),"rng_state":rng.state,"floating":floating,"carried":carried_cargo,"dropped":dropped,"abandoned":abandoned,"configuration":configuration.duplicate(true),"seed":seed_value,"secured":secured,
        "unsecured":unsecured,"events":events.duplicate(true),"routes":routes.duplicate(true)}
