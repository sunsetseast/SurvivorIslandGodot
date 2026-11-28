class_name LivingCampRules
extends RefCounted
## Pure integer rules; SeasonSimulation owns all mutable state.
const STEP_SECONDS := 30 # .25 real seconds * 120
const SCALE := 7200 # units per condition point; hourly rates divide exactly per step
const MAXIMUM := 100 * SCALE
const RATES := {"nutrition":-7200, "hydration":-14400, "awake":-10800,
    "light":-3600, "strenuous":-14400, "rest":43200, "sweat":-5400}
const CAPACITY := {"fire":3, "shelter":6, "shore":4, "spring":3, "trail":3, "work":3}
const DURATION := {"fire":80, "shelter":240, "shore":100, "spring":16, "trail":80, "work":80}

static func calendar(seconds: int) -> Dictionary:
    # Day changes at 06:00; the first day starts two hours later, at 08:00.
    var offset := seconds + 7200
    var day_number := offset / 86400 + 1
    var time := (offset % 86400 + 21600) % 86400
    var hour := time / 3600
    var period := "daylight"
    if hour < 5 or hour >= 19: period = "night"
    elif hour < 7: period = "dawn"
    elif hour >= 17: period = "dusk"
    return {"day":day_number, "seconds":time, "period":period}

static func initial(fatigue: float) -> Dictionary:
    return {"nutrition":85 * SCALE, "hydration":85 * SCALE,
        "energy":roundi(clampf(100 - 35 * fatigue, 65, 100) * SCALE), "health":MAXIMUM}

static func effort(activity: String, stage: String) -> String:
    if stage != "occupied": return "awake"
    if activity == "shelter": return "rest"
    if activity in ["work", "trail"]: return "strenuous"
    if activity == "fire": return "light"
    return "awake"

static func advance(condition: Dictionary, classification: String) -> void:
    condition.nutrition = maxi(0, int(condition.nutrition) + RATES.nutrition / 120)
    condition.hydration = maxi(0, int(condition.hydration) + (RATES.hydration + (RATES.sweat if classification == "strenuous" else 0)) / 120)
    var energy_rate: int = RATES.rest if classification == "rest" else RATES.awake + int(RATES.get(classification, 0) if classification != "awake" else 0)
    condition.energy = clampi(int(condition.energy) + energy_rate / 120, 0, MAXIMUM)
    # Health stays stable until the complete survival loop is available.

static func efficiency(condition: Dictionary) -> float:
    return clampf(.5 + .5 * mini(condition.energy, mini(condition.nutrition, condition.hydration)) / MAXIMUM, .5, 1)

static func profile(attributes: Dictionary) -> Dictionary:
    # Missing optional ratings use neutral 5; never mutate the approved catalog.
    var work := 1.1 - rating(attributes, "laziness")
    return {"work":work, "social":(rating(attributes, "connections") + rating(attributes, "likeability")) / 2,
        "fire":.8 * rating(attributes, "firemaking") + .1 * rating(attributes, "focus") + .1 * rating(attributes, "dexterity"),
        "ability":.75 * rating(attributes, "campcraft") + .1 * rating(attributes, "dexterity") + .1 * rating(attributes, "strength") + .05 * work}

static func rating(attributes: Dictionary, key: String) -> float:
    return clampf(float(attributes.get(key, 5)), 1, 10) / 10

static func choose(person: Dictionary, condition: Dictionary, derived: Dictionary, available: Array[String], rng: RandomNumberGenerator) -> String:
    var best := ""
    var score := -INF
    for activity: String in available:
        var value := .3
        match activity:
            "shelter": value += 6 * maxf(0, .85 - float(condition.energy) / MAXIMUM)
            "spring": value += 8 * maxf(0, .8 - float(condition.hydration) / MAXIMUM)
            "work": value += derived.work * derived.ability * efficiency(condition)
            "fire": value += derived.work * derived.fire * efficiency(condition)
            "shore":
                value += derived.social * .4
                if derived.get("food_available", false): value += 8 * maxf(0, .8 - float(condition.nutrition) / MAXIMUM)
        if person.get("last_activity", "") == activity: value *= .45
        # Current site avoids travel. Variation only at activity boundaries.
        if person.get("site", "") == activity: value += .15
        value += rng.randf_range(0, .3)
        if value > score:
            score = value
            best = activity
    return best
