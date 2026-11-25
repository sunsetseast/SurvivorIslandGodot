class_name SurvivorSupabaseTransport
extends Node

const PROJECT := "https://hjmhgibfbxgzqvfdomoj.supabase.co"
const PUBLISHABLE_KEY := "sb_publishable_BSuFgKMH99hsYlRJw_-LwQ_IsC2MhyH"
const RESPONSE_BYTES := 1_100_000

# Overrides are injected by local integration tests only.
var endpoint := PROJECT
var publishable_key := PUBLISHABLE_KEY
var _requests: Dictionary = {}

class Exchange extends RefCounted:
    signal finished(response: Dictionary)

func send(path: String, method: HTTPClient.Method, body: Dictionary = {}, token := "") -> Dictionary:
    var request := HTTPRequest.new()
    # Browser Fetch already decompresses responses. If the gateway exposes the
    # Content-Encoding header, HTTPRequest would try to decompress them again.
    request.accept_gzip = not OS.has_feature("web")
    request.timeout = 15.0
    request.max_redirects = 0
    request.body_size_limit = RESPONSE_BYTES
    add_child(request)
    var exchange := Exchange.new()
    _requests[request] = exchange
    request.request_completed.connect(_completed.bind(request), CONNECT_ONE_SHOT)
    var headers := PackedStringArray(["apikey: " + publishable_key, "Content-Type: application/json", "Accept: application/json"])
    if not token.is_empty():
        headers.append("Authorization: Bearer " + token)
    var content := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body, "", true, true)
    if request.request(endpoint + path, headers, method, content) != OK:
        _requests.erase(request)
        request.queue_free()
        return {"ok": false, "status": 0, "code": "offline"}
    return await exchange.finished

func cancel() -> void:
    var active := _requests
    _requests = {}
    for request: HTTPRequest in active:
        var exchange: Exchange = active[request]
        request.cancel_request()
        request.queue_free()
        exchange.finished.emit({"ok": false, "status": 0, "code": "cancelled"})

func _completed(result: int, status: int, headers: PackedStringArray, body: PackedByteArray,
        request: HTTPRequest) -> void:
    var exchange: Exchange = _requests[request]
    _requests.erase(request)
    request.queue_free()
    if result != HTTPRequest.RESULT_SUCCESS:
        exchange.finished.emit({"ok": false, "status": 0, "code": "offline"})
        return
    var parser := JSON.new()
    var parsed: Variant = parser.data if body.is_empty() or parser.parse(body.get_string_from_utf8()) == OK else null
    var retry_after := 0
    for header: String in headers:
        if header.to_lower().begins_with("retry-after:"):
            var value := header.get_slice(":", 1).strip_edges()
            retry_after = clampi(value.to_int(), 0, 86400) if value.is_valid_int() else 60
    var ok := status >= 200 and status < 300 and (body.is_empty() or parsed is Dictionary or parsed is Array)
    var code := ""
    if not ok:
        if status >= 200 and status < 300:
            code = "invalid_response"
        elif parsed is Dictionary:
            code = String(parsed.get("error_code", parsed.get("code", "")))
    exchange.finished.emit({"ok": ok, "status": status, "code": code,
        "retry_after": retry_after, "data": parsed if ok else null})
