class_name SurvivorCloudSaveService
extends Node

signal updated(slot: int, status: String)

const RPC := "/rest/v1/rpc/player_data"
const LIMIT := 256_000
const PERIOD := 90_000

var auth: SurvivorAuthService
var store: LocalDataStore
var saves: LocalSaveProvider
var _due: Dictionary = {}
var _failures: Dictionary = {}
var _failed_checkpoint: Dictionary = {}
var _busy := false

func _init(authentication: SurvivorAuthService) -> void:
    auth = authentication

func bind(cache: LocalDataStore, provider: LocalSaveProvider) -> void:
    store = cache
    saves = provider
    _due.clear()
    _failures.clear()
    _failed_checkpoint.clear()
    if saves != null:
        for slot in range(1, LocalSaveProvider.SLOTS + 1):
            if saves.inspect(slot).status == "valid":
                schedule(slot, true)

func call_data(action: String, args := {}) -> Dictionary:
    var result := await auth.authorized(RPC, HTTPClient.METHOD_POST, {"action": action, "args": args})
    if not result.ok:
        return {"status": result.code if not String(result.code).is_empty() else "unavailable",
            "retry_after": result.get("retry_after", 0)}
    if action == "list":
        return _decode_list(result.data)
    return result.data if result.data is Dictionary else {"status": "invalid_response"}

static func _decode_list(data: Variant) -> Dictionary:
    if data is not Array:
        return {"status": "invalid_response"}
    for row: Variant in data:
        if row is not Dictionary or row.get("id") is not String \
                or not SurvivorIdentityService.valid_account(row.id) \
                or not GameStateData.identity(row.get("season_id")) \
                or not GameStateData.integer(row.get("revision"), 1, SaveCodec.MAX_REVISION) \
                or not GameStateData.integer(row.get("day"), 1, 416667) \
                or not GameStateData.integer(row.get("tick"), 0, 1_000_000_000):
            return {"status": "invalid_response"}
    return {"status": "listed", "items": data}

func slot_status(index: int, entry: Dictionary) -> String:
    if entry.get("state", {}).get("ruleset_version") == 2:
        return "Saved locally · cloud support pending"
    if store == null:
        return "Saved locally only"
    var sync := record(index)
    var revision := int(entry.save_revision)
    if sync.get("season") == entry.state.season_id:
        if sync.get("blocked") in ["conflict", "missing"]:
            return "Conflict detected"
        if sync.has("blocked"):
            return "Sync failed"
        if sync.get("paused", false):
            return "Saved locally only"
        if int(sync.get("revision", 0)) > 0 and int(sync.get("ack", 0)) == revision:
            return "Synced to cloud"
    if _failed_checkpoint.get(index) == entry.fingerprint:
        return "Sync failed"
    return "Sync pending"

func schedule(slot: int, immediate := false) -> void:
    if saves != null:
        var entry := saves.inspect(slot)
        if entry.status == "valid" and not supports_state(entry.state):
            return
    if store == null:
        return
    var now := Time.get_ticks_msec()
    if immediate and not _failures.has(slot):
        _due[slot] = now
    elif not _due.has(slot):
        _due[slot] = now + PERIOD

func record(slot: int) -> Dictionary:
    var best := {}
    if store == null:
        return best
    for generation in 2:
        var raw: Variant = store.read("sync-%d-%d" % [slot, generation])
        var wrapper: Variant = JSON.parse_string(raw) if raw is String and raw.begins_with("{") else null
        if wrapper is not Dictionary or wrapper.get("payload") is not String \
                or wrapper.payload.sha256_text() != wrapper.get("checksum"):
            continue
        var value: Variant = JSON.parse_string(wrapper.payload)
        if value is Dictionary and GameStateData.integer(value.get("serial"), 1, SaveCodec.MAX_REVISION) \
                and int(value.serial) > int(best.get("serial", 0)):
            best = value
    return best

func write_record(slot: int, value: Dictionary) -> bool:
    var next := value.duplicate()
    next.serial = int(record(slot).get("serial", 0)) + 1
    var payload := JSON.stringify(next, "", true, true)
    var key := "sync-%d-%d" % [slot, int(next.serial) % 2]
    var raw := JSON.stringify({"payload": payload, "checksum": payload.sha256_text()})
    return store.write(key, raw) and store.read(key) == raw

func reset(slot: int) -> bool:
    _due.erase(slot)
    _failures.erase(slot)
    _failed_checkpoint.erase(slot)
    # Writing a newer empty record prevents a previous queue from attaching
    # itself to the next season placed in this local slot.
    return store == null or write_record(slot, {})

func mark_guest_import(slot: int, state: Dictionary) -> bool:
    if store == null or not supports_state(state):
        return false
    if not write_record(slot, {"season": state.season_id, "guest_import": true}):
        return false
    schedule(slot, true)
    return true

func restore(slot: int, id: String, requested_revision: int, replace_local := false) -> String:
    if _busy or store == null:
        return "busy"
    _busy = true
    var epoch := auth.epoch
    var before := saves.inspect(slot)
    var result := await call_data("get", {"id": id, "revision": requested_revision})
    if epoch == auth.epoch and replace_local and result.status == "missing":
        result = await call_data("get", {"id": id})
    _busy = false
    if epoch != auth.epoch:
        return "cancelled"
    if result.status != "found":
        return result.status
    var entry := SaveCodec.decode(String(result.get("snapshot", "")))
    if entry.status != "valid" or entry.state.season_id != result.save.season_id:
        return "invalid_snapshot"
    if replace_local and int(result.save.revision) != requested_revision:
        var existing := record(slot)
        existing.cloud = result.save
        existing.blocked = "conflict"
        return "conflict" if write_record(slot, existing) else "local_storage"
    if not replace_local and int(result.revision) == int(result.save.revision):
        for index in range(1, LocalSaveProvider.SLOTS + 1):
            if index != slot and record(index).get("id") == id and saves.inspect(index).status == "valid":
                return "already_cached"
    if before.get("fingerprint") != saves.inspect(slot).get("fingerprint"):
        return "local_changed"
    if before.status != "empty" and not (replace_local and before.status == "valid"):
        return "choose_empty_slot"
    # Stage a fence before installing a checkpoint. A crash or storage error
    # between the two writes cannot upload a partially associated checkpoint.
    if not write_record(slot, {"season": entry.state.season_id, "blocked": "restore_incomplete"}):
        return "local_storage"
    var saved := saves.replace(slot, entry.state, int(before.get("save_revision", 0)))
    if saved.status != "valid":
        return saved.status
    # An explicitly selected historical revision remains local until the player
    # chooses to preserve it as a new cloud save.
    var historical: bool = int(result.revision) != int(result.save.revision)
    if not write_record(slot, {"id": id, "season": entry.state.season_id,
        "revision": int(result.revision), "ack": int(saved.save_revision), "paused": historical}):
        return "local_storage"
    _due.erase(slot)
    _failures.erase(slot)
    _failed_checkpoint.erase(slot)
    return "restored"

func resolve(slot: int, choice: String, confirmed_revision: int) -> String:
    if _busy or store == null:
        return "busy"
    var sync := record(slot)
    if choice == "cloud":
        return await restore(slot, String(sync.get("id", "")), confirmed_revision, true)
    var local := saves.inspect(slot)
    if local.status != "valid" or not supports_state(local.state):
        return "invalid_snapshot"
    if choice == "local" and confirmed_revision > 0:
        sync = {"id": sync.id, "season": local.state.season_id, "revision": confirmed_revision}
    elif choice == "both":
        sync = {"season": local.state.season_id}
    else:
        return "cancelled"
    if not write_record(slot, sync):
        return "local_storage"
    _failures.erase(slot)
    _failed_checkpoint.erase(slot)
    schedule(slot, true)
    return "queued"

func delete_cloud(id: String, revision: int) -> String:
    if _busy or store == null:
        return "busy"
    _busy = true
    var epoch := auth.epoch
    var result := await call_data("delete", {"id": id, "expected": revision})
    _busy = false
    if auth.epoch != epoch:
        return "cancelled"
    if result.status == "deleted":
        for slot in range(1, LocalSaveProvider.SLOTS + 1):
            var sync := record(slot)
            if sync.get("id") == id:
                sync = {"season": sync.get("season"), "id": id, "paused": true}
                if not write_record(slot, sync):
                    return "local_storage"
    return result.status

func _process(_delta: float) -> void:
    if _busy or store == null or _due.is_empty():
        return
    var now := Time.get_ticks_msec()
    for slot: int in _due:
        if now >= int(_due[slot]):
            _due.erase(slot)
            _busy = true
            _sync_slot(slot)
            return

func _sync_slot(slot: int) -> void:
    var epoch := auth.epoch
    var sync := record(slot)
    var local := saves.inspect(slot)
    if local.status != "valid" or not supports_state(local.state):
        _busy = false
        return
    if sync.get("season") != local.state.season_id:
        sync = {"season": local.state.season_id}
    if sync.has("blocked") or sync.get("paused", false) \
            or int(sync.get("ack", 0)) == int(local.save_revision):
        _busy = false
        return
    if not sync.has("operation"):
        var raw := SaveCodec.encode(local.state, int(local.save_revision), int(local.timestamp))
        if raw.to_utf8_buffer().size() > LIMIT:
            _busy = false
            _failed_checkpoint[slot] = local.fingerprint
            updated.emit(slot, "save_too_large")
            return
        if not sync.has("id"):
            sync.id = _uuid()
        sync.snapshot = raw
        sync.operation = _uuid()
        sync.pending = int(local.save_revision)
        if not write_record(slot, sync):
            _busy = false
            _failed_checkpoint[slot] = local.fingerprint
            updated.emit(slot, "local_storage")
            return
    var args := {"id": sync.id, "expected": int(sync.get("revision", 0)),
        "operation": sync.operation, "snapshot": sync.snapshot, "guest_import": sync.get("guest_import", false)}
    var result := await call_data("put", args)
    _busy = false
    if epoch != auth.epoch:
        return
    var status: String = result.status
    var current := record(slot)
    if current.get("operation") != sync.operation:
        return
    if status == "saved":
        _failures.erase(slot)
        _failed_checkpoint.erase(slot)
        sync.revision = int(result.revision)
        sync.ack = int(sync.pending)
        sync.erase("guest_import")
        _clear_operation(sync)
        if not write_record(slot, sync):
            status = "local_storage"
        if int(saves.inspect(slot).get("save_revision", 0)) != int(sync.ack):
            schedule(slot)
    elif status in ["conflict", "missing", "capacity", "already_imported", "invalid_snapshot",
            "operation_mismatch", "invalid"]:
        sync.blocked = status
        sync.cloud = result.get("save", {})
        _clear_operation(sync)
        if not write_record(slot, sync):
            status = "local_storage"
    elif status != "cancelled":
        var count := mini(int(_failures.get(slot, 0)) + 1, 6)
        _failures[slot] = count
        var delay := maxi(int(result.get("retry_after", 0)), mini(300, 5 * (1 << count)))
        _due[slot] = Time.get_ticks_msec() + delay * 1000 + randi_range(100, 1200)
        status = "pending_offline"
    if status == "local_storage":
        _failed_checkpoint[slot] = local.fingerprint
    updated.emit(slot, status)

func _clear_operation(sync: Dictionary) -> void:
    sync.erase("operation")
    sync.erase("snapshot")
    sync.erase("pending")

func _uuid() -> String:
    var bytes := Crypto.new().generate_random_bytes(16)
    bytes[6] = (bytes[6] & 15) | 64
    bytes[8] = (bytes[8] & 63) | 128
    var hex := bytes.hex_encode()
    return "%s-%s-%s-%s-%s" % [hex.left(8), hex.substr(8, 4), hex.substr(12, 4),
        hex.substr(16, 4), hex.right(12)]

static func supports_state(state: Dictionary) -> bool:
    return state.get("ruleset") in [SeasonSimulation.RULESET, SurvivorSeasonConfiguration.RULESET] and state.get("ruleset_version") == 1
