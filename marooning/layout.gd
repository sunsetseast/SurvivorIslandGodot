class_name MarooningLayout
extends Resource
## Distances in metres; route IDs and semantic markers are Phase 4D.2 contracts.
@export var ship_origin := Vector3(0, -1.5, 0)
@export var deck_y := 1.9
@export var reward := Vector3(76, .5, 20)
@export var landing := Vector3(0, .5, 178)
@export var reward_id := "fishing-equipment-preview"
@export var raft_mounts: Array[Vector3] = [Vector3(-9, .55, -8), Vector3(9, .55, -8), Vector3(9, .55, 5)]
@export var rival_exits: Array[Vector3] = [Vector3(-180, 0, 100), Vector3(180, 0, 100)]

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
