extends SceneTree
class Backend:
    extends RefCounted
    var record := ""
    var unavailable := false
    func read_record() -> Dictionary:
        return {"status": "unavailable" if unavailable else "ok", "value": record}
    func write_record(value: String) -> int:
        if unavailable:
            return -1
        record = value
        return 0
    func clear_record() -> int:
        if unavailable:
            return -1
        record = ""
        return 0
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr(message)
func _initialize() -> void:
    var backend := Backend.new()
    var store := SurvivorCredentialStore.new(backend)
    store.clear()
    var tokens := {"account": "12345678-1234-1234-1234-123456789abc", "access": "access-secret",
        "refresh": "refresh-one", "expires": 100}
    store.replace(tokens)
    check(not backend.record.contains("access-secret") and not backend.record.contains("expires"), "Minimum persistence")
    check(store.restore_record().refresh == "refresh-one", "Relaunch refresh")
    tokens.refresh = "refresh-two"
    store.replace(tokens)
    check(store.restore_record().refresh == "refresh-two", "Rotation")
    backend.unavailable = true
    store.clear()
    check(store.read().is_empty() and store.restore_record().is_empty(), "Unavailable logout blocked")
    backend.unavailable = false
    check(SurvivorCredentialStore.new(backend).restore_record().is_empty(), "Failed delete cannot restore old identity")
    store.clear()
    check(backend.record.is_empty(), "Delete")
    tokens.account = "abcdefab-1234-1234-1234-123456789abc"
    store.replace(tokens)
    check(store.restore_record().account == tokens.account, "Account switch")
    store.clear()
    var memory := SurvivorCredentialStore.new()
    memory.replace(tokens)
    check(memory.restore_record().is_empty() and memory.read().refresh == tokens.refresh, "Safe memory fallback")
    print("Credential mock: ", failures, " failures")
    quit(int(failures > 0))
