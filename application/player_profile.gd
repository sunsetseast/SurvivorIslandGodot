class_name PlayerProfile
extends RefCounted
## Local guest identity can later be bound to an authenticated account.
## Preferences live outside the season and are device-specific in Phase 3A.

const DEFAULTS := {"camera_steering": false, "sensitivity": 1.0, "economy": false, "run": false}
var guest_id := ""
var preferences := DEFAULTS.duplicate()
var available := false
var _store: LocalDataStore

func _init(store: LocalDataStore) -> void:
    _store = store
    var raw: Variant = _store.read("guest")
    if raw == "":
        raw = GameStateData.new_id()
        available = _store.write("guest", raw) and _store.read("guest") == raw
    else:
        available = GameStateData.identity(raw)
    guest_id = raw if available else GameStateData.new_id()
    var settings: Variant = _store.read("preferences")
    if settings is not String or settings.is_empty():
        return
    var parser := JSON.new()
    if parser.parse(settings) != OK:
        return
    var parsed: Variant = parser.data
    if parsed is not Dictionary or parsed.get("version") != 1:
        return
    for key: String in DEFAULTS:
        var value: Variant = parsed.get(key)
        if key == "sensitivity":
            if value in [.65, 1.0, 1.4]:
                preferences[key] = float(value)
        elif value is bool:
            preferences[key] = value

func set_preference(key: String, value: Variant) -> bool:
    preferences[key] = value
    var record := preferences.duplicate()
    record["version"] = 1
    return _store.write("preferences", JSON.stringify(record))
