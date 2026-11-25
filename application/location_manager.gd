class_name LocationManager
extends Node

const PRESENTATIONS := {"tonsai": "res://tonsai/camp.tscn"}
var camp: TonsaiCamp

func enter(id: String, session: GameSession, profile: PlayerProfile) -> bool:
    if not PRESENTATIONS.has(id):
        return false
    leave()
    var scene := load(PRESENTATIONS[id]) as PackedScene
    camp = scene.instantiate() as TonsaiCamp
    camp.session = session
    camp.profile = profile
    add_child(camp)
    if not camp.loaded:
        leave()
        return false
    return true

func leave() -> void:
    if camp == null:
        return
    if camp.loaded:
        camp.end_talk()
        if camp.local_host != null:
            camp.local_host.bind_physical_location("")
    remove_child(camp)
    camp.queue_free()
    camp = null
