class_name LocalSaveProvider
extends PersistenceProvider

const SLOTS := 3
var store: LocalDataStore

func _init(data_store: LocalDataStore) -> void:
    store = data_store

func inspect(slot: int) -> Dictionary:
    if slot < 1 or slot > SLOTS:
        return {"status": "invalid_slot"}
    var best := {"status": "empty"}
    var corrupt := false
    var fingerprint := ""
    for generation in 2:
        var raw: Variant = store.read(_key(slot, generation))
        if raw == null:
            return {"status": "unavailable"}
        fingerprint += String(raw).sha256_text()
        if raw == "":
            continue
        var entry := SaveCodec.decode(raw)
        if entry.status == "unsupported":
            best = entry
            continue
        if entry.status == "corrupt":
            corrupt = true
            continue
        if best.status == "unsupported":
            continue
        if best.status == "empty" or int(entry.save_revision) > int(best.save_revision):
            best = entry
            best["generation"] = generation
    if corrupt and best.status == "empty":
        best = {"status": "corrupt"}
    best["fingerprint"] = fingerprint
    best["recovered"] = corrupt
    return best

func write(slot: int, state: Dictionary, expected_revision: int) -> Dictionary:
    return _write(slot, state, expected_revision, false)

# A user-confirmed cloud replacement keeps the prior generation recoverable.
func replace(slot: int, state: Dictionary, expected_revision: int) -> Dictionary:
    return _write(slot, state, expected_revision, true)

func _write(slot: int, state: Dictionary, expected_revision: int, replacement: bool) -> Dictionary:
    var previous := inspect(slot)
    if not previous.status in ["empty", "valid"]:
        return previous
    if int(previous.get("save_revision", 0)) != expected_revision:
        return {"status": "conflict"}
    if not replacement and previous.status == "valid" and (previous.state.season_id != state.season_id \
            or int(previous.state.revision) > int(state.revision)):
        return {"status": "conflict"}
    var next_revision := expected_revision + 1
    var raw := SaveCodec.encode(state, next_revision, int(Time.get_unix_time_from_system()))
    if SaveCodec.decode(raw).status != "valid":
        return {"status": "invalid_save"}
    var key := _key(slot, 1 - int(previous.get("generation", 1)))
    if not store.write(key, raw) or store.read(key) != raw:
        return {"status": "write_failed"}
    return {"status": "valid", "save_revision": next_revision}

func erase(slot: int) -> bool:
    if slot < 1 or slot > SLOTS:
        return false
    var previous := inspect(slot)
    if previous.status == "unavailable":
        return false
    var newest := int(previous.get("generation", 1))
    return store.erase(_key(slot, 1 - newest)) and store.erase(_key(slot, newest))

func _key(slot: int, generation: int) -> String:
    return "slot-%d-%d" % [slot, generation]
