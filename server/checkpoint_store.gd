extends RefCounted

const RPC := "/rest/v1/rpc/phase3c_checkpoint"
const MAX_BYTES := 1_000_000

var transport: SurvivorSupabaseTransport
var key: String
var revision := 0
var last_bytes := 0
var last_usec := 0

func _init(adapter: SurvivorSupabaseTransport, secret: String) -> void:
    transport = adapter
    key = secret

func read_latest() -> Dictionary:
    var response := await transport.send(RPC, HTTPClient.METHOD_POST, {"secret": key, "expected": -1, "payload": null})
    if not response.ok or response.data is not Dictionary or not response.data.has("revision"):
        return {}
    revision = int(response.data.revision)
    return response.data

func write_latest(state: Dictionary) -> bool:
    var started := Time.get_ticks_usec()
    var raw := JSON.stringify(state, "", true, true)
    last_bytes = raw.to_utf8_buffer().size()
    if last_bytes > MAX_BYTES:
        return false
    var response := await transport.send(RPC, HTTPClient.METHOD_POST,
        {"secret": key, "expected": revision, "payload": state})
    last_usec = Time.get_ticks_usec() - started
    if not response.ok or response.data is not Dictionary or response.data.get("revision") != revision + 1:
        return false
    revision += 1
    return true
