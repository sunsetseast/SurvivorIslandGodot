class_name SurvivorAuthService
extends Node

signal changed
signal refresh_finished

const AUTH := "/auth/v1"
const MIN_PASSWORD := 8
const POST := HTTPClient.METHOD_POST

var transport: SurvivorSupabaseTransport
var account := ""
var email := ""
var epoch := 0
var _credentials := SurvivorCredentialStore.new()
var _refreshing := false
var _refresh_delay := 0
var _recovery := false
var _sign_in_attempt := 0

func _init(adapter: SurvivorSupabaseTransport) -> void:
    transport = adapter

func restore_session() -> void:
    var record := _credentials.restore_record()
    if record.is_empty() or not account.is_empty():
        return
    var generation := epoch
    var attempt := _sign_in_attempt
    var result := await transport.send(AUTH + "/token?grant_type=refresh_token", POST,
        {"refresh_token": record.refresh})
    if generation != epoch or attempt != _sign_in_attempt:
        return
    if result.ok:
        if _accept(result.data, false, str(record.account)):
            changed.emit()
        else:
            clear()
    elif int(result.status) in [400, 401, 403]:
        clear()


func register(address: String, password: String) -> Dictionary:
    if not _email_valid(address) or password.length() < MIN_PASSWORD or password.length() > 72:
        return _failure("invalid_form")
    return await _public("/signup", {"email": address, "password": password})

func login(address: String, password: String) -> Dictionary:
    if not _email_valid(address) or password.is_empty() or password.length() > 72:
        return _failure("invalid_form")
    return await _public("/token?grant_type=password", {"email": address, "password": password}, true)

func verify(address: String, code: String, recovery: bool) -> Dictionary:
    if not _email_valid(address) or code.length() < 6 or code.length() > 10 or not code.is_valid_int():
        return _failure("invalid_code")
    return await _public("/verify", {"email": address, "token": code,
        "type": "recovery" if recovery else "email"}, true, recovery)

func resend(address: String, recovery: bool) -> Dictionary:
    if not _email_valid(address):
        return _failure("invalid_form")
    if recovery:
        return await _public("/recover", {"email": address})
    return await _public("/resend", {"type": "signup", "email": address})

func set_password(password: String) -> Dictionary:
    if not _recovery or password.length() < MIN_PASSWORD or password.length() > 72:
        return _failure("invalid_form")
    var generation := epoch
    var result := await authorized(AUTH + "/user", HTTPClient.METHOD_PUT, {"password": password}, true)
    if generation == epoch and result.ok:
        await logout()
    return result

func logout() -> Dictionary:
    var token := String(_credentials.read().get("access", ""))
    clear()
    if token.is_empty():
        return {"ok": true}
    return await transport.send(AUTH + "/logout?scope=local", POST, {}, token)

func recovery_pending() -> bool:
    return _recovery

func delete_account(password: String) -> Dictionary:
    if password.is_empty() or password.length() > 72:
        return _failure("invalid_form")
    return await authorized("/functions/v1/delete-player", POST, {"password": password})

func clear() -> void:
    epoch += 1
    _refreshing = false
    _refresh_delay = 0
    _credentials.clear()
    account = ""
    email = ""
    _recovery = false
    transport.cancel()
    refresh_finished.emit()
    changed.emit()

# Only the multiplayer transport receives this short-lived credential.
func multiplayer_access_token() -> String:
    if account.is_empty() or _recovery:
        return ""
    var generation := epoch
    var tokens := _credentials.read()
    if int(tokens.expires) <= int(Time.get_unix_time_from_system()) + 75:
        await _refresh(generation, String(tokens.access))
    if generation != epoch:
        return ""
    tokens = _credentials.read()
    return String(tokens.access) if int(tokens.expires) > int(Time.get_unix_time_from_system()) + 5 else ""

func authorized(path: String, method: HTTPClient.Method, body: Dictionary = {},
        recovery_allowed := false) -> Dictionary:
    if account.is_empty() or (_recovery and not recovery_allowed):
        return _failure("sign_in_required")
    var generation := epoch
    var tokens := _credentials.read()
    if int(tokens.expires) <= int(Time.get_unix_time_from_system()) + 60:
        if not await _refresh(generation, String(tokens.access)):
            return _failure("refresh_unavailable")
        tokens = _credentials.read()
    if epoch != generation:
        return _failure("cancelled")
    var result := await transport.send(path, method, body, tokens.access)
    if epoch != generation:
        return _failure("cancelled")
    if result.status == 401 or (result.status == 403 and result.code == "42501"):
        if not await _refresh(generation, String(tokens.access)):
            return _failure("refresh_unavailable")
        if epoch != generation:
            return _failure("cancelled")
        result = await transport.send(path, method, body, _credentials.read().access)
    return result if epoch == generation else _failure("cancelled")

func _public(path: String, body: Dictionary, starts_session := false, recovery := false) -> Dictionary:
    var generation := epoch
    if starts_session:
        _sign_in_attempt += 1
    var attempt := _sign_in_attempt
    var result := await transport.send(AUTH + path, POST, body)
    if generation != epoch or (starts_session and attempt != _sign_in_attempt):
        return _failure("cancelled")
    if result.ok and starts_session:
        if not _accept(result.data, recovery):
            return _failure("invalid_session")
        changed.emit()
    # Auth payloads (including tokens) stay inside this service.
    result.erase("data")
    return result

func _refresh(generation: int, expired: String) -> bool:
    while _refreshing and generation == epoch:
        await refresh_finished
    if generation != epoch or account.is_empty():
        return false
    var tokens := _credentials.read()
    if tokens.access != expired:
        return true
    if Time.get_ticks_msec() < _refresh_delay:
        return false
    _refreshing = true
    var result := await transport.send(AUTH + "/token?grant_type=refresh_token", POST,
        {"refresh_token": tokens.refresh})
    if generation != epoch:
        return false
    _refreshing = false
    var accepted: bool = result.ok and _accept(result.data, _recovery)
    if not accepted:
        if int(result.status) in [400, 401, 403] or result.ok:
            clear()
            return false
        _refresh_delay = Time.get_ticks_msec() + maxi(5, int(result.get("retry_after", 0))) * 1000
    refresh_finished.emit()
    return accepted

func _accept(value: Variant, recovery: bool, expected := "") -> bool:
    if value is not Dictionary or value.get("user") is not Dictionary:
        return false
    var user: Dictionary = value.user
    var id: String = str(user.get("id", ""))
    if (not expected.is_empty() and id != expected) or not SurvivorIdentityService.valid_account(id) or (not account.is_empty() and account != id) \
            or user.get("email_confirmed_at") == null:
        return false
    var access: Variant = value.get("access_token")
    var refresh: Variant = value.get("refresh_token")
    var expires: Variant = value.get("expires_in")
    if access is not String or refresh is not String or access.is_empty() or refresh.is_empty() \
            or not GameStateData.integer(expires, 1, 86400):
        return false
    _credentials.replace({"account": id, "access": access, "refresh": refresh,
        "expires": int(Time.get_unix_time_from_system()) + int(expires)})
    account = id
    email = str(user.get("email", ""))
    _recovery = recovery
    return true

func _email_valid(value: String) -> bool:
    return value.length() <= 254 and value.get_slice_count("@") == 2 \
        and not value.get_slice("@", 0).is_empty() and not value.get_slice("@", 1).is_empty()

func _failure(code: String) -> Dictionary:
    return {"ok": false, "status": 0, "code": code}
