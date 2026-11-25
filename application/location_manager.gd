class_name LocationManager
extends Node

const PRESENTATIONS := {"tonsai": "res://tonsai/camp.tscn"}
var camp: TonsaiCamp
var loading := false
var last_load_usec := 0
var last_unload_usec := 0

func enter(id: String, session: GameSession, profile: PlayerProfile) -> bool:
    if not PRESENTATIONS.has(id):
        return false
    leave()
    loading = true
    var started := Time.get_ticks_usec()
    # Synchronous by design: Web export has no worker threads. No retained scene cache.
    var scene := load(PRESENTATIONS[id]) as PackedScene
    if scene == null:
        loading = false
        return false
    camp = scene.instantiate() as TonsaiCamp
    camp.session = session
    camp.profile = profile
    add_child(camp)
    loading = false
    last_load_usec = Time.get_ticks_usec() - started
    if not camp.loaded:
        leave()
        return false
    return true

func leave() -> void:
    if camp == null:
        return
    var started := Time.get_ticks_usec()
    if camp.loaded:
        camp.end_talk()
        if camp.local_host != null:
            camp.local_host.bind_physical_location("")
    camp.process_mode = Node.PROCESS_MODE_DISABLED
    remove_child(camp)
    camp.queue_free()
    camp = null
    last_unload_usec = Time.get_ticks_usec() - started
