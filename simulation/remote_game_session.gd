class_name RemoteGameSession
extends GameSession

const Wire := preload("res://multiplayer/wire.gd")
const RETRY_SECONDS := [1.0, 2.0, 4.0, 8.0, 12.0, 15.0]
const INPUT_MS := 55

signal changed

var room: Dictionary = {}
var status := "Connecting…"
var connected := false
var active := false
var has_state := false
var round_trip_ms := 120.0
var _url: String
var _access_token: Callable
var _socket: WebSocketPeer
var _generation := 0
var _retry := 0
var _retry_at := 0
var _deadline := 0
var _heartbeat_at := 0
var _sent_ping := 0
var _renew_at := 0
var _input_at := 0
var _next_move := 0
var _next_command := 1
var _stopped := false
var _suspended := false
var _auth_started := false
var _projection := {}
var _journal: Array = []
var _motion := {}
var _previous := {}
var _frame_at := 0
var _frame_interval := 100
var _request: Dictionary = {}
var _command_at := 0

func _init(url: String, token_provider: Callable) -> void:
    _url = url
    _access_token = token_provider

func reconnect() -> void:
    _stopped = false
    _retry = 0
    _retry_at = 0

func close() -> void:
    _stopped = true
    _disconnect()

func suspend(value: bool) -> void:
    _suspended = value
    if value:
        _disconnect()
        _status("Connection paused")
    elif not _stopped:
        reconnect()

func poll() -> void:
    if _stopped or _suspended:
        return
    var now := Time.get_ticks_msec()
    if _socket == null:
        if now >= _retry_at:
            _connect()
        return
    _socket.poll()
    match _socket.get_ready_state():
        WebSocketPeer.STATE_OPEN:
            if not _auth_started:
                _auth_started = true
                _authenticate(_generation, "auth")
            for _index in Wire.QUEUE:
                if _socket == null or _socket.get_available_packet_count() <= 0:
                    break
                var message := Wire.decode(_socket.get_packet(), Wire.SERVER_BYTES)
                if not message.is_empty():
                    _receive(message, now)
            if _socket == null:
                return
            if now >= _heartbeat_at:
                _heartbeat_at = now + 3000
                _sent_ping = now
                Wire.send(_socket, "ping")
            if connected and now >= _renew_at:
                _renew_at = now + 25_000
                _authenticate(_generation, "renew")
            if not _request.is_empty() and now >= _command_at + 6000:
                _request.clear()
                _status("Interaction timed out")
        WebSocketPeer.STATE_CLOSING:
            pass
        WebSocketPeer.STATE_CLOSED:
            _lost()
            return
    if now >= _deadline:
        _lost()

func _connect() -> void:
    _generation += 1
    _auth_started = false
    _socket = WebSocketPeer.new()
    Wire.configure(_socket)
    _deadline = Time.get_ticks_msec() + 30_000
    if _socket.connect_to_url(_url) != OK:
        _lost()
    else:
        _status("Connecting…" if _retry == 0 else "Reconnecting…")

func _authenticate(generation: int, kind: String) -> void:
    var token: String = await _access_token.call()
    if generation != _generation or _socket == null:
        return
    if token.is_empty():
        _lost()
        return
    if not Wire.send(_socket, kind, {"token": token}):
        _lost()

func _disconnect() -> void:
    _generation += 1
    if _socket != null:
        _socket.close()
        _socket = null
    connected = false
    active = false
    has_state = false
    _previous.clear()
    _journal.clear()
    _request.clear()
    _next_move = 0
    resolved.emit({"ok": true, "event": {"type": "conversation_closed"}})

func _lost() -> void:
    _disconnect()
    if _retry >= RETRY_SECONDS.size():
        _stopped = true
        _status("Connection unavailable · Reconnect to retry")
        return
    _retry_at = Time.get_ticks_msec() + roundi(RETRY_SECONDS[_retry] * 1000.0)
    _retry += 1
    _status("Connection lost · Reconnecting…")

func _receive(message: Dictionary, now: int) -> void:
    _deadline = now + 12_000
    match message.type:
        "authorized":
            if not connected:
                connected = true
                _retry = 0
                _renew_at = now + 25_000
                _status("Connected")
        "room":
            var next_room := {"code": message.code, "roster": message.roster, "controlled": message.controlled,
                "started": message.started, "host": message.host}
            if room != next_room:
                room = next_room
                changed.emit()
        "camp":
            _projection.cast = message.cast
            _projection.objects = message.objects
        "state":
            _frame_interval = clampi(now - _frame_at, 70, 180)
            _frame_at = now
            _previous = _motion if has_state else message.movement
            _motion = message.movement
            _projection.merge(message.view, true)
            _next_command = int(message.next_command)
            var first_frame := not has_state
            has_state = true
            if active != message.active or first_frame:
                active = message.active
                if not active:
                    resolved.emit({"ok": true, "event": {"type": "conversation_closed"}})
                _status("Season active" if active else "Season suspended · Waiting for both players")
        "journal_reset":
            _journal.clear()
        "journal":
            for record: Dictionary in message.records:
                _journal.append(record)
            if _journal.size() > CampSimulation.MAX_RECORDS:
                _journal = _journal.slice(-CampSimulation.MAX_RECORDS)
        "receipt":
            if _request.get("id") != message.result.get("id"):
                return
            if message.result.ok and _request.kind == "talk.respond":
                _next_command = maxi(_next_command, int(_request.seq) + 1)
            elif not message.result.ok:
                _status(_message(message.result.reason))
            _request.clear()
            resolved.emit(message.result)
        "pong":
            round_trip_ms = lerpf(round_trip_ms, clampf(now - _sent_ping, 0.0, 400.0), .55)
        "error":
            _status(_message(message.reason))
        "fatal":
            close()
            _status(_message(message.reason))

func _message(reason: String) -> String:
    match reason:
        "connection_replaced": return "This account connected from another client"
        "authorization_lost": return "Authorization ended · Sign in again"
        "room_in_use": return "This server already has a private session"
        "room_unavailable": return "Private session unavailable for this account"
        "two_players_required": return "Both assigned players must connect to start"
        "checkpoint_pending": return "Checkpoint in progress · Try again"
        "unavailable": return "Move closer to the contestant and try again"
        _: return reason.replace("_", " ").capitalize()

func _status(value: String) -> void:
    if status != value:
        status = value
        changed.emit()

func request_room(type: String, fields := {}) -> void:
    if connected:
        Wire.send(_socket, type, fields)

func send_intent(direction: Vector3, running: bool, dive: bool, vertical: float) -> void:
    var now := Time.get_ticks_msec()
    if not active or not connected or now < _input_at:
        return
    _input_at = now + INPUT_MS
    _next_move += 1
    Wire.send(_socket, "move", {"seq": _next_move, "x": direction.x, "z": direction.z, "run": running,
        "dive": dive, "vertical": vertical})

func submit(request: Dictionary) -> Dictionary:
    if not active or not connected or not _request.is_empty():
        return {"ok": false, "reason": "session_unavailable"}
    _request = request.duplicate()
    _request.erase("actor")
    _request.seq = _next_command
    _command_at = Time.get_ticks_msec()
    if not Wire.send(_socket, "talk", _request):
        _request.clear()
        return {"ok": false, "reason": "connection_unavailable"}
    return {"ok": true, "pending": true}

func view(location: String) -> Dictionary:
    if location != "tonsai" or _projection.is_empty():
        return {}
    var result := _projection.duplicate()
    result.controlled = room.get("controlled", "")
    result.knowledge = _journal.duplicate(true)
    result.pose = {}
    return result

func activity(location: String, id: String) -> Dictionary:
    if location == "tonsai":
        return _projection.get("cast", {}).get(id, {})
    return {}

func movement(id: String) -> Array:
    return _motion.get(id, []) if has_state else []

func movement_age() -> float:
    return clampf(float(Time.get_ticks_msec() - _frame_at) * .001, 0, .22)

func interpolated(id: String) -> Dictionary:
    var row := movement(id)
    if row.is_empty():
        return {}
    var old: Array = _previous.get(id, row)
    var fraction := clampf(float(Time.get_ticks_msec() - _frame_at) / _frame_interval, 0, 1)
    return {"position": Wire.position_from(old).lerp(Wire.position_from(row), fraction),
        "heading": lerp_angle(old[3], row[3], fraction), "locomotion": row[4],
        "speed": Vector2(row[6], row[8]).length(), "talking": row[9]}
