class_name SurvivorSeasonConfiguration
extends RefCounted

const RULESET := "configurable-single-player"
const VERSION := 1
const NAMES := ["Tagi", "Moto", "Fang", "Bayon", "Luvu", "Tika", "Ratu", "Soka", "Yanuya", "Galang", "Salani", "Nuku", "Manono", "Jabeni", "Tandang", "Zhan Hu", "Ikabula", "La Mina"]
const COLORS := ["red", "orange", "blue", "purple", "green"]
var seed_value: int = 1
var count: int = 2
var method: String = "Balanced"
var tribes: Array = []
var _ratings: Dictionary = {}

static func fingerprint(catalog: SurvivorContestantCatalog) -> String:
    return JSON.stringify(catalog.all(), "", true).sha256_text()

func assign(catalog: SurvivorContestantCatalog) -> void:
    if method == "Brains / Brawn / Beauty":
        count = 3
    elif method == "Battle of the Sexes":
        count = 2
    var identities := tribes.duplicate(true)
    tribes.clear()
    for i in count:
        tribes.append({"id":"tribe-%d" % (i + 1), "name":NAMES[i], "color":["red", "blue", "green"][i], "label":"", "members":[]})
    if identities.size() == count:
        for i in count:
            tribes[i].name = identities[i].name
            tribes[i].color = identities[i].color
    var entries := catalog.all()
    _ratings.clear()
    for entry: Dictionary in entries:
        _ratings[int(entry.id)] = [50.0 if entry.gender == "male" else 0.0, float(entry.totals.Physical), float(entry.totals.Mental), float(entry.totals.Social)]
    var random := RandomNumberGenerator.new()
    random.seed = seed_value
    for i in range(entries.size() - 1, 0, -1):
        var j := random.randi_range(0, i)
        var temp: Dictionary = entries[i]
        entries[i] = entries[j]
        entries[j] = temp
    if method in ["Brains / Brawn / Beauty", "Battle of the Sexes"]:
        var labels := ["Mental", "Physical", "Social"] if count == 3 else ["male", "female"]
        for i in count:
            tribes[i].label = ["Brains", "Brawn", "Beauty"][i] if count == 3 else labels[i].capitalize()
        for entry: Dictionary in entries:
            var group := labels.find(entry.trait if count == 3 else entry.gender)
            if group >= 0:
                tribes[group].members.append(int(entry.id))
    else:
        for i in entries.size():
            tribes[i % count].members.append(int(entries[i].id))
        if method == "Balanced":
            # Bounded local search over equal-capacity swaps, including gender
            # variance and all three actual category totals. Seeded ties persist.
            var score := _score(catalog)
            for attempt in 600:
                var a := random.randi_range(0, count - 1)
                var b := (a + random.randi_range(1, count - 1)) % count
                var x := random.randi_range(0, tribes[a].members.size() - 1)
                var y := random.randi_range(0, tribes[b].members.size() - 1)
                _swap(a, x, b, y)
                var candidate := _score(catalog)
                if candidate < score:
                    score = candidate
                else:
                    _swap(a, x, b, y)
    for tribe: Dictionary in tribes:
        tribe.members.sort()

func _swap(a: int, x: int, b: int, y: int) -> void:
    var temp: int = tribes[a].members[x]
    tribes[a].members[x] = tribes[b].members[y]
    tribes[b].members[y] = temp

func _score(_catalog: SurvivorContestantCatalog) -> float:
    var sums: Array = []
    for tribe: Dictionary in tribes:
        var values := [0.0, 0.0, 0.0, 0.0]
        for id: int in tribe.members:
            for i in 4:
                values[i] += _ratings[id][i]
        sums.append(values)
    var score := 0.0
    for a in count:
        for b in range(a + 1, count):
            for i in 4:
                score += pow(sums[a][i] - sums[b][i], 2)
    return score

func validate(catalog: SurvivorContestantCatalog, selected: int) -> bool:
    if not catalog.available or catalog.all().size() != 18 or catalog.get_by_id(selected).is_empty() or count not in [2, 3] or tribes.size() != count:
        return false
    if method not in ["Random", "Balanced", "Manual", "Brains / Brawn / Beauty", "Battle of the Sexes"]:
        return false
    if method == "Brains / Brawn / Beauty" and count != 3 or method == "Battle of the Sexes" and count != 2:
        return false
    var seen := []
    var names := []
    var colors := []
    for i in count:
        if tribes[i] is not Dictionary:
            return false
        var tribe: Dictionary = tribes[i]
        var label: String = ["Brains", "Brawn", "Beauty"][i] if method == "Brains / Brawn / Beauty" else (["Male", "Female"][i] if method == "Battle of the Sexes" else "")
        if tribe.get("label") != label:
            return false
        if tribe.get("id") != "tribe-%d" % (i + 1) or tribe.get("name") not in NAMES or tribe.name in names or tribe.get("color") not in COLORS or tribe.color in colors or tribe.get("members") is not Array or tribe.members.size() != 18 / count:
            return false
        names.append(tribe.name)
        colors.append(tribe.color)
        for id: Variant in tribe.members:
            if not GameStateData.integer(id, 1, 18) or id in seen or catalog.get_by_id(int(id)).is_empty():
                return false
            var entry := catalog.get_by_id(int(id))
            if method == "Brains / Brawn / Beauty" and entry.trait != ["Mental", "Physical", "Social"][i] or method == "Battle of the Sexes" and entry.gender != ["male", "female"][i]:
                return false
            seen.append(id)
    return seen.size() == 18 and selected in seen and not ("red" in colors and "orange" in colors)

func configuration(catalog: SurvivorContestantCatalog, setup: SurvivorNewSeasonSetup) -> Dictionary:
    if not setup.validate(catalog) or not validate(catalog, setup.selected_id):
        return {}
    var result := {"seed":str(seed_value), "selected":setup.selected_id, "information":setup.information_mode, "catalog":fingerprint(catalog), "method":method, "tribes":tribes.duplicate(true)}
    var offscreen := 2
    for tribe: Dictionary in result.tribes:
        tribe.members.sort()
        tribe["location"] = "tonsai" if setup.selected_id in tribe.members else "camp-%d" % offscreen
        if tribe.location != "tonsai":
            offscreen += 1
    return result

static func roster_for(config: Dictionary, catalog: SurvivorContestantCatalog, owner: String) -> Dictionary:
    var result := {}
    for entry: Dictionary in catalog.all():
        for tribe: Dictionary in config.tribes:
            if int(entry.id) in tribe.members:
                var controlled: bool = int(entry.id) == int(config.selected)
                result[str(int(entry.id))] = {"catalog":int(entry.id), "name":entry.name, "tribe":tribe.id, "location":tribe.location, "controller":"human" if controlled else "ai", "owner":owner if controlled else "", "status":"active", "attributes":entry.attributes.duplicate(true), "state":entry.defaults.duplicate(true)}
    return result
