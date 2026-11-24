class_name CampSimulation
extends RefCounted
## Provisional behavior provider. Receives physical events from controllers and
## publishes intentions keyed by identity. Conversation records have one owner.

const PLAYER := &"player"
const CONTESTANTS := {
    &"cirie": "Cirie", &"yul": "Yul", &"parvati": "Parvati", &"jeremy": "Jeremy", &"kelley": "Kelley",
}
const ACTIVITIES := {
    &"fire": {"label": "Tending the fire", "pose": &"Idle"},
    &"shelter": {"label": "Resting at the shelter", "pose": &"Seated"},
    &"shore": {"label": "Taking a moment on the beach", "pose": &"Idle"},
    &"spring": {"label": "Visiting the water well", "pose": &"Idle"},
    &"trail": {"label": "Walking the freshwater trail", "pose": &"Idle"},
    &"work": {"label": "Working at the camp rack", "pose": &"Idle"},
}
const TOPICS := {&"camp": "How's camp feeling?", &"water": "Where's the freshwater?"}
const REPLIES := {
    &"cirie": "I like hearing what people say when they think no one is keeping score.",
    &"yul": "We should figure out which chores each person wants to handle.",
    &"parvati": "The walk down to the beach gets you away from the whole group.",
    &"jeremy": "First thing is making sure the fire keeps going.",
    &"kelley": "The shelter's a good place to see who's coming and going.",
}
var _people: Dictionary[StringName, Dictionary] = {}
var _reservations: Dictionary[StringName, StringName] = {}
var _random := RandomNumberGenerator.new()
var _conversation: StringName = &""
var arrivals := 0

func _init() -> void:
    _random.randomize()
    for id: StringName in CONTESTANTS:
        _people[id] = {"activity": &"", "left": 0.0, "stage": &"waiting", "journal": []}
    _people[PLAYER] = {"journal": []}

func intent(id: StringName) -> StringName:
    var person := _people[id]
    if person.activity != &"":
        return person.activity
    var choices: Array = ACTIVITIES.keys().filter(func(key: StringName) -> bool:
        return not _reservations.has(key))
    if choices.is_empty():
        return &""
    var selected: StringName = choices[_random.randi_range(0, choices.size() - 1)]
    _reservations[selected] = id
    person.activity = selected
    person.stage = &"travel"
    return selected

func reserve_first(id: StringName, activity: StringName) -> void:
    if _reservations.has(activity):
        return
    _reservations[activity] = id
    _people[id].activity = activity
    _people[id].stage = &"travel"

func arrived(id: StringName, activity: StringName) -> bool:
    var person := _people[id]
    if person.activity != activity or person.stage != &"travel":
        return false
    person.stage = &"occupied"
    person.left = _random.randf_range(11.0, 28.0)
    arrivals += 1
    return true

func travel_failed(id: StringName) -> void:
    var person := _people[id]
    _reservations.erase(person.activity)
    person.activity = &""
    person.stage = &"waiting"

func advance(id: StringName, seconds: float) -> bool:
    var person := _people[id]
    if person.stage != &"occupied" or _conversation == id:
        return false
    person.left = maxf(0.0, person.left - seconds)
    if person.left > 0.0:
        return false
    travel_failed(id)
    return true

func can_talk(id: StringName) -> bool:
    return CONTESTANTS.has(id) and _conversation == &""

func begin_conversation(id: StringName) -> bool:
    if not can_talk(id):
        return false
    _conversation = id
    return true

func respond(id: StringName, topic: StringName) -> String:
    if _conversation != id or not TOPICS.has(topic):
        return ""
    var reply: String = REPLIES[id]
    if topic == &"water":
        reply = "Take the trail inland from the shelter. Go past the big fig and follow it east."
    var event := {"with": id, "topic": topic, "reply": reply}
    _people[PLAYER].journal.append(event)
    _people[id].journal.append({"with": PLAYER, "topic": topic, "reply": reply})
    return reply

func end_conversation(id: StringName) -> void:
    if _conversation == id:
        _conversation = &""

func knowledge_for(owner: StringName) -> Array:
    if not _people.has(owner):
        return []
    return _people[owner].journal.duplicate(true)
