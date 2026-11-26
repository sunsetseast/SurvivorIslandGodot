class_name SurvivorContestantCatalog
extends RefCounted
## Read-only selection metadata. Missing private data means selection is unavailable.
## Returned values are deep copies; neither browsing nor editing them starts a season.

const PRIVATE_PATH := "res://private_cast/catalog.json"
const UNAVAILABLE_MESSAGE := "Contestant selection is unavailable in this build."
const GROUPS := {
    "Physical": {"strength": "Strength", "speed": "Speed", "endurance": "Endurance",
        "dexterity": "Dexterity", "balance": "Balance"},
    "Mental": {"memory": "Memory", "puzzles": "Puzzles", "fortitude": "Fortitude",
        "awareness": "Awareness", "focus": "Focus"},
    "Social": {"connections": "Connections", "likeability": "Likeability",
        "interrogation": "Interrogation", "deception": "Deception", "alliances": "Alliances"},
    "Strategic tendencies": {"bigmove": "Big moves", "idolhunt": "Idol hunting", "idolshare": "Idol sharing",
        "honesty": "Honesty", "risk": "Risk", "aggression": "Aggression",
        "paratend": "Paranoia tendency", "leader": "Leadership"},
    "Survival": {"fishing": "Fishing", "laziness": "Camp-work avoidance",
        "firemaking": "Firemaking", "campcraft": "Campcraft"},
}
const DEFAULT_FIELDS := {
    "health": TYPE_INT, "threat": TYPE_INT, "challengeThreat": TYPE_INT,
    "teamPlayer": TYPE_INT, "roles": TYPE_ARRAY, "firewood": TYPE_INT,
    "bamboo": TYPE_INT, "palms": TYPE_INT, "coconuts": TYPE_INT,
    "fish": TYPE_INT, "fish1": TYPE_INT, "fish2": TYPE_INT, "fish3": TYPE_INT,
    "water": TYPE_INT, "hunger": TYPE_INT, "rest": TYPE_INT, "hasVote": TYPE_BOOL,
    "votePenalty": TYPE_NIL, "extraVotes": TYPE_INT, "suspicion": TYPE_INT,
}
const ENTRY_FIELDS := ["id", "name", "gender", "trait", "style", "original_season",
    "appearance_season", "attributes", "totals", "defaults", "portrait_path", "model_path"]

var available: bool:
    get:
        return not _entries.is_empty()
var unavailable_reason: String:
    get:
        return "" if available else UNAVAILABLE_MESSAGE

var _entries: Array[Dictionary] = []
var _by_id: Dictionary = {}

func _init(source_path: String = PRIVATE_PATH) -> void:
    # The optional path exists for isolated technical validation, never a fallback cast.
    if not FileAccess.file_exists(source_path):
        return
    var file := FileAccess.open(source_path, FileAccess.READ)
    if file == null:
        return
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK:
        return
    var document: Variant = parser.data
    if not document is Dictionary or document.get("version") != 1 \
            or not document.get("entries") is Array or document.entries.is_empty():
        return
    var entries: Array[Dictionary] = []
    var by_id := {}
    for raw: Variant in document.entries:
        if not _valid_entry(raw):
            return
        var entry: Dictionary = _integers(raw)
        if by_id.has(entry.id):
            return
        _freeze(entry)
        entries.append(entry)
        by_id[entry.id] = entry
    entries.make_read_only()
    by_id.make_read_only()
    _entries = entries
    _by_id = by_id

func all() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for entry: Dictionary in _entries:
        result.append(entry.duplicate(true))
    return result

func get_by_id(id: int) -> Dictionary:
    return _by_id[id].duplicate(true) if _by_id.has(id) else {}

func eligible(trait_filter: String = "All", gender: String = "All") -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for entry: Dictionary in _entries:
        if trait_filter.to_lower() != "all" and entry.trait.to_lower() != trait_filter.to_lower():
            continue
        if gender.to_lower() != "all" and entry.gender.to_lower() != gender.to_lower():
            continue
        result.append(entry.duplicate(true))
    return result

static func _valid_entry(value: Variant) -> bool:
    if not value is Dictionary or value.size() != ENTRY_FIELDS.size():
        return false
    for key: String in ENTRY_FIELDS:
        if not value.has(key):
            return false
    if not _whole(value.id) or value.id <= 0:
        return false
    for key: String in ["name", "gender", "trait", "style", "original_season", "appearance_season"]:
        if not value[key] is String or value[key].strip_edges().is_empty():
            return false
    if value.gender not in ["male", "female"] or value.trait not in ["Physical", "Mental", "Social"]:
        return false
    if not value.attributes is Dictionary or value.attributes.size() != 27 \
            or not value.totals is Dictionary or value.totals.size() != 3 \
            or not value.defaults is Dictionary or value.defaults.size() != DEFAULT_FIELDS.size():
        return false
    for group: String in GROUPS:
        var total := 0
        for field: String in GROUPS[group]:
            var rating: Variant = value.attributes.get(field)
            if not _whole(rating) or rating < 1 or rating > 10:
                return false
            total += int(rating)
        if group in ["Physical", "Mental", "Social"]:
            if not _whole(value.totals.get(group)) or value.totals[group] != total:
                return false
    for field: String in DEFAULT_FIELDS:
        var initial: Variant = value.defaults.get(field)
        if not value.defaults.has(field):
            return false
        if DEFAULT_FIELDS[field] == TYPE_INT:
            if not _whole(initial):
                return false
        elif typeof(initial) != DEFAULT_FIELDS[field]:
            return false
    if not value.defaults.roles.is_empty():
        return false
    return _private_asset(value.portrait_path, "portraits/", ".webp", false) \
        and _private_asset(value.model_path, "models/", ".glb", true)

static func _private_asset(value: Variant, folder: String, extension: String, optional: bool) -> bool:
    if not value is String:
        return false
    if optional and value.is_empty():
        return true
    var prefix := "res://private_cast/" + folder
    if not value.begins_with(prefix):
        return false
    var filename: String = value.trim_prefix(prefix)
    return not filename.is_empty() and filename.ends_with(extension) \
        and "/" not in filename and "\\" not in filename and ".." not in filename

static func _whole(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value)) \
        and float(value) == floor(float(value))

static func _integers(value: Variant) -> Variant:
    if value is float and _whole(value):
        return int(value)
    if value is Dictionary:
        var result := {}
        for key: Variant in value:
            result[key] = _integers(value[key])
        return result
    if value is Array:
        var result := []
        for item: Variant in value:
            result.append(_integers(item))
        return result
    return value

static func _freeze(value: Variant) -> void:
    if value is Dictionary:
        for item: Variant in value.values():
            _freeze(item)
        value.make_read_only()
    elif value is Array:
        for item: Variant in value:
            _freeze(item)
        value.make_read_only()
