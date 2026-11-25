class_name SurvivorCredentialStore
extends RefCounted
## Platform boundary: Web/Android remain memory-only until a secure adapter exists.
## The iOS adapter persists only account + rotating refresh credential.
const BLOCK := "user://credential-restore-blocked"
var _tokens: Dictionary = {}
var _backend: Object
var secure_status := "memory_only"

func _init(backend: Object = null) -> void:
    _backend = backend
    if _backend == null and OS.has_feature("ios") and Engine.has_singleton("SurvivorKeychain"):
        _backend = Engine.get_singleton("SurvivorKeychain")

func read() -> Dictionary:
    return _tokens.duplicate()

func restore_record() -> Dictionary:
    if _backend == null or FileAccess.file_exists(BLOCK):
        return {}
    var result: Dictionary = _backend.call("read_record")
    secure_status = str(result.get("status", "unavailable"))
    var record: Variant = JSON.parse_string(str(result.get("value", "")))
    if secure_status != "ok" or record is not Dictionary:
        return {}
    if not SurvivorIdentityService.valid_account(str(record.get("account", ""))) or record.get("refresh") is not String:
        return {}
    return record

func replace(value: Dictionary, persist := true) -> void:
    if not persist:
        clear()
        _tokens = value.duplicate()
        return
    _tokens = value.duplicate()
    if _backend == null:
        return
    # Fail closed across relaunch if a write fails (including account replacement).
    _block_restore()
    var record := JSON.stringify({"account": value.account, "refresh": value.refresh})
    secure_status = "ok" if int(_backend.call("write_record", record)) == 0 else "unavailable"
    if secure_status == "ok":
        DirAccess.remove_absolute(BLOCK)

func clear() -> void:
    _tokens.clear()
    if _backend != null:
        _block_restore()
        secure_status = "ok" if int(_backend.call("clear_record")) == 0 else "unavailable"
        if secure_status == "ok":
            DirAccess.remove_absolute(BLOCK)

func _block_restore() -> void:
    var file := FileAccess.open(BLOCK, FileAccess.WRITE)
    if file != null:
        file.store_string("blocked")
        file.close()
