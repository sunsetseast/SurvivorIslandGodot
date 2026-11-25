class_name SurvivorMultiplayerWire
extends RefCounted

const VERSION := 1
const REQUEST_BYTES := 4096
const SERVER_BYTES := 65_536
const BUFFER_BYTES := 131_072
const QUEUE := 32
const MAX_PENDING_BYTES := 65_536
const CODE_LENGTH := 12
const CLIENT_FIELDS := {
    "auth": ["token"], "renew": ["token"], "create": [], "join": ["code"],
    "resume": [], "start": [], "ping": [],
    "move": ["seq", "x", "z", "run", "dive", "vertical"],
    "talk": ["seq", "id", "kind", "target", "topic"],
}

static func configure(socket: WebSocketPeer) -> void:
    socket.inbound_buffer_size = BUFFER_BYTES
    socket.outbound_buffer_size = BUFFER_BYTES
    socket.max_queued_packets = QUEUE

static func decode(packet: PackedByteArray, limit: int) -> Dictionary:
    if packet.is_empty() or packet.size() > limit:
        return {}
    var parser := JSON.new()
    if parser.parse(packet.get_string_from_utf8()) != OK:
        return {}
    var parsed: Variant = parser.data
    if parsed is Dictionary and parsed.get("v") == VERSION and parsed.get("type") is String:
        return parsed
    return {}

static func valid_request(message: Dictionary) -> bool:
    var type: String = message.get("type", "")
    if not CLIENT_FIELDS.has(type):
        return false
    var fields: Array = CLIENT_FIELDS[type]
    if message.size() != fields.size() + 2 or not message.has_all(fields):
        return false
    match type:
        "auth", "renew":
            return message.token is String and _jwt_format(message.token)
        "join":
            return message.code is String and message.code.length() == CODE_LENGTH and message.code.is_valid_hex_number(false)
        "move":
            return GameStateData.integer(message.seq, 1, 2_000_000_000) \
                and GameStateData.number(message.x, -1, 1) and GameStateData.number(message.z, -1, 1) \
                and Vector2(message.x, message.z).length_squared() <= 1.002 \
                and message.run is bool and message.dive is bool and GameStateData.number(message.vertical, -1, 1)
        "talk":
            return GameStateData.integer(message.seq, 1, 2_000_000_000) \
                and message.id is String and GameStateData.identity(message.id) \
                and message.kind in ["talk.begin", "talk.respond", "talk.end"] \
                and message.target is String and SeasonCatalog.TONSAI_CAST.has(message.target) \
                and message.topic is String and (message.topic.is_empty() or CampSimulation.TOPICS.has(message.topic))
    return true

static func _jwt_format(token: String) -> bool:
    if token.length() > 3500 or token.get_slice_count(".") != 3:
        return false
    for part: String in token.split("."):
        if part.is_empty():
            return false
        for index in part.length():
            var character := part.unicode_at(index)
            if not ((character >= 65 and character <= 90) or (character >= 97 and character <= 122)
                    or (character >= 48 and character <= 57) or character == 45 or character == 95):
                return false
    return true

static func send(socket: WebSocketPeer, type: String, fields := {}) -> bool:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return false
    if socket.get_current_outbound_buffered_amount() > MAX_PENDING_BYTES:
        return false
    var message: Dictionary = fields.duplicate()
    message.v = VERSION
    message.type = type
    return socket.send_text(JSON.stringify(message, "", false)) == OK

static func position_from(row: Array) -> Vector3:
    return Vector3(row[0], row[1], row[2])
