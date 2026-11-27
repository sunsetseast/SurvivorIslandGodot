class_name MarooningLayout
extends Resource
## Distances in metres; route IDs and semantic markers are Phase 4D.2 contracts.
@export var ship_origin := Vector3(0, -1.5, 0)
@export var deck_y := 1.9
@export var reward := Vector3(0, .5, 115)
@export var landing := Vector3(0, .5, 178)
@export var reward_id := "fishing-equipment-preview"
@export var raft_mounts: Array[Vector3] = [Vector3(-10, .55, 30), Vector3(10, .55, 30), Vector3(20, .55, 31.7834151)]
@export var rival_exits: Array[Vector3] = [Vector3(-180, 0, 100), Vector3(180, 0, 100)]

# Editable deck anchors in metres, kept off the centre mast and bow corridor.
@export var collection_centres: Array[Vector3] = [Vector3(-2.95,1.9,1.0),Vector3(2.95,1.9,1.0),Vector3(-2.95,1.9,5.8)]
@export var resource_islands: Array[Vector3] = [Vector3(-2.7,1.9,-1.8),Vector3(2.7,1.9,-1.8),Vector3(-.65,1.9,2.6),Vector3(.65,1.9,4.4),Vector3(2.7,1.9,6.5)]
func supply_anchors() -> Array[Vector3]:
    var points: Array[Vector3] = []
    # Five compact resource islands; opposing traffic uses x≈±1.5 and central links.
    for centre: Vector3 in resource_islands:
        for i in 10:
            points.append(centre+Vector3((i%2)*.45-.225,0,(i/2)*.42-.84))
    return points

func arrange_supplies(items: Dictionary, seed_value: int) -> void:
    var random := RandomNumberGenerator.new()
    random.seed = seed_value+381
    var pool := supply_anchors()
    var definitions := MarooningSupplyCatalog.definitions()
    var order := items.keys()
    var ranks := {"food":0,"cooking":1,"water":1,"shelter":2,"tool":3,"fire":4,"storage":4}
    order.sort_custom(func(a: String,b: String) -> bool:
        var left: int = ranks[definitions[items[a].type].category]
        var right: int = ranks[definitions[items[b].type].category]
        return left<right if left!=right else a<b)
    var side := -1.0 if random.randf()<.5 else 1.0
    for id: String in order:
        var category: String = definitions[items[id].type].category
        var centre := Vector3(side*2.7,deck_y,-1.8)
        if category=="shelter": centre = Vector3(side*.65,deck_y,2.6 if side<0 else 4.4)
        elif category in ["tool","fire","storage"]: centre = Vector3(2.7,deck_y,6.5)
        var best := 0
        var score := INF
        for index in pool.size():
            var distance := pool[index].distance_to(centre)+random.randf()*.16
            if distance<score:
                best=index
                score=distance
        items[id].position = pool[best]
        pool.remove_at(best)
        side = -side

func bed(_x: float, z: float) -> float:
    return clampf((z - 158.0) * .09, -9, 2.2)

func routes(config: Dictionary) -> Dictionary:
    var result := {}
    var rival := 0
    for tribe: Dictionary in config.tribes:
        var own: bool = config.selected in tribe.members
        result[tribe.id] = {"route_id": "player-landing" if own else "rival-exit-%d" % rival,
            "destination": landing if own else rival_exits[rival], "camp": tribe.location,
            "raft_id":"raft-%d" % result.size(), "raft_mount":raft_mounts[result.size()]}
        if not own:
            rival += 1
    return result
