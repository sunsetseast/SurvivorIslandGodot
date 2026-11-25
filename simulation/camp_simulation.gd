class_name CampSimulation
extends RefCounted
## Activity reservations, semantic transitions and participant-owned memories.

const ACTIVITIES := {
    "fire": {"label": "Tending the fire", "pose": &"Idle"},
    "shelter": {"label": "Resting at the shelter", "pose": &"Seated"},
    "shore": {"label": "Taking a moment on the beach", "pose": &"Idle"},
    "spring": {"label": "Visiting the water well", "pose": &"Idle"},
    "trail": {"label": "Walking the freshwater trail", "pose": &"Idle"},
    "work": {"label": "Working at the camp rack", "pose": &"Idle"},
}
const TOPICS := {"camp": "How's camp feeling?", "water": "Where's the freshwater?"}
const REPLIES := {
    "cirie": "I like hearing what people say when they think no one is keeping score.",
    "yul": "We should figure out which chores each person wants to handle.",
    "parvati": "The walk down to the beach gets you away from the whole group.",
    "jeremy": "First thing is making sure the fire keeps going.",
    "kelley": "The shelter's a good place to see who's coming and going.",
}
const MAX_RECORDS := 500

var people: Dictionary = {}
var reservations: Dictionary = {}
var objects := {"fire": {"lit": true}}
var conversations: Dictionary = {}
var arrivals := 0

func add(id: String, activity: String) -> void:
    people[id] = {"activity": "", "deadline": 0, "stage": "waiting", "journal": []}
    if not activity.is_empty():
        _reserve(id, activity, 0)

func _reserve(id: String, activity: String, tick: int) -> void:
    reservations[activity] = id
    var person: Dictionary = people[id]
    person.activity = activity
    person.stage = "travel"
    person.deadline = tick + 24

func arrived(id: String, activity: String, tick: int, rng: RandomNumberGenerator) -> bool:
    var person: Dictionary = people[id]
    if person.activity != activity or person.stage != "travel" or conversations.values().has(id):
        return false
    person.stage = "occupied"
    person.deadline = tick + rng.randi_range(44, 112)
    arrivals += 1
    return true

func travel_failed(id: String, activity: String, tick: int) -> bool:
    var person: Dictionary = people[id]
    if person.activity != activity or person.stage != "travel" or conversations.values().has(id):
        return false
    _release(person, tick)
    return true

func _release(person: Dictionary, tick: int) -> void:
    reservations.erase(person.activity)
    person.activity = ""
    person.stage = "waiting"
    person.deadline = tick + 5

func schedule(id: String, tick: int, physical: bool, rng: RandomNumberGenerator) -> void:
    var person: Dictionary = people[id]
    if conversations.values().has(id):
        person.deadline += 1
        return
    if tick < int(person.deadline):
        return
    match person.stage:
        "waiting":
            var choices: Array = []
            for activity: String in ACTIVITIES:
                if not reservations.has(activity):
                    choices.append(activity)
            if not choices.is_empty():
                _reserve(id, choices[rng.randi_range(0, choices.size() - 1)], tick)
        "travel":
            if not physical:
                arrived(id, person.activity, tick, rng)
        "occupied":
            _release(person, tick)

func respond(actor: String, target: String, topic: String, tick: int, receipt: String) -> String:
    var reply: String = REPLIES.get(target, "We should check in with the others.")
    if topic == "water":
        reply = "Take the trail inland from the shelter. Go past the big fig and follow it east."
    for pair: Array in [[actor, target], [target, actor]]:
        var journal: Array = people[pair[0]].journal
        journal.append({"with": pair[1], "topic": topic, "reply": reply, "tick": tick, "id": receipt})
        if journal.size() > MAX_RECORDS:
            journal.pop_front()
    return reply

func snapshot() -> Dictionary:
    return {"people": people.duplicate(true), "objects": objects.duplicate(true), "arrivals": arrivals}

func restore(data: Dictionary) -> void:
    people = data.people.duplicate(true)
    objects = data.objects.duplicate(true)
    arrivals = int(data.arrivals)
    for id: String in people:
        var person: Dictionary = people[id]
        person.deadline = int(person.deadline)
        for record: Dictionary in person.journal:
            record.tick = int(record.tick)
        var activity: String = person.activity
        if not activity.is_empty():
            reservations[activity] = id
