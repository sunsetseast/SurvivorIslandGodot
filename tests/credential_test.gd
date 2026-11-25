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
class Transport:
    extends SurvivorSupabaseTransport
    var response: Dictionary = {}
    var calls := 0
    func send(_path: String, _method: HTTPClient.Method, _body: Dictionary = {}, _token := "") -> Dictionary:
        calls += 1
        await get_tree().process_frame
        return response.duplicate(true)
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr(message)
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
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
    var transport := Transport.new()
    root.add_child(transport)
    var auth := SurvivorAuthService.new(transport)
    auth._credentials = store
    root.add_child(auth)
    var account := tokens.account as String
    var payload := {"user": {"id": account, "email_confirmed_at": "confirmed"},
        "access_token": "access-new", "refresh_token": "refresh-new", "expires_in": 3600}
    transport.response = {"ok": true, "status": 200, "data": payload}
    store.replace(tokens)
    await auth.restore_session()
    check(auth.account == account and store.restore_record().refresh == "refresh-new", "Verified restore and rotation")
    auth.clear()
    store.replace(tokens)
    payload.user.id = "12345678-1234-1234-1234-123456789abc"
    transport.response.data = payload
    await auth.restore_session()
    check(auth.account.is_empty() and backend.record.is_empty(), "Reject wrong restored identity")
    payload.user.id = account
    for status in [0, 401]:
        store.replace(tokens)
        transport.response = {"ok": false, "status": status}
        await auth.restore_session()
        check(auth.account.is_empty(), "Failed restoration never authenticates")
        check(not backend.record.is_empty() if status == 0 else backend.record.is_empty(), "Temporary vs revoked credential")
    store.replace(tokens)
    transport.response = {"ok": true, "status": 200, "data": payload}
    auth.restore_session()
    auth.clear()
    await process_frame
    await process_frame
    check(auth.account.is_empty() and backend.record.is_empty(), "Logout epoch fences pending restoration")
    check(auth._accept(payload, true), "Recovery session accepted")
    check(backend.record.is_empty(), "Recovery credentials never persist")
    auth.clear()
    auth.free()
    transport.free()
    print("Credential mock: ", failures, " failures")
    quit(int(failures > 0))
