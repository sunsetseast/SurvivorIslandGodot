class_name TonsaiNpc
extends CampHumanoidMotor

var contestant: StringName
var simulation: CampSimulation
var destinations: Dictionary[StringName, Vector3]
var agent: NavigationAgent3D
var target_activity: StringName = &""
var delay := 0.0
var talking_to: Node3D
var at_activity := false
var travel_distance := 0.0
var _no_progress := 0.0
var _approach := Vector3.INF

func _ready() -> void:
    collision_layer = 8
    collision_mask = 1 | 4
    super()
    agent = NavigationAgent3D.new()
    agent.radius = RADIUS
    agent.path_desired_distance = .55
    agent.target_desired_distance = .60
    agent.path_max_distance = 2.5
    add_child(agent)
    var identifier := Label3D.new()
    identifier.text = simulation.CONTESTANTS[contestant]
    identifier.position.y = 1.92
    identifier.pixel_size = .0035
    identifier.font_size = 45
    identifier.outline_size = 8
    identifier.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    identifier.visibility_range_end = 15.0
    add_child(identifier)

func _physics_process(delta: float) -> void:
    if is_instance_valid(talking_to):
        walk_direction(Vector3.ZERO, false, delta, false)
        face_point(talking_to.global_position, delta)
        set_motion(&"Talk")
        return
    if delay > 0.0:
        delay -= delta
        walk_direction(Vector3.ZERO, false, delta, motion_clip == &"Idle")
        return
    if target_activity.is_empty():
        target_activity = simulation.intent(contestant)
        if not target_activity.is_empty():
            _approach = destinations[target_activity]
            agent.target_position = _approach
        return
    if at_activity:
        walk_direction(Vector3.ZERO, false, delta, false)
        if simulation.advance(contestant, delta):
            _leave()
        return
    if _close_to(_approach) and simulation.arrived(contestant, target_activity):
        at_activity = true
        var pose: StringName = simulation.ACTIVITIES[target_activity].pose
        set_motion(&"SitDown" if pose == &"Seated" else pose)
        return
    var next := agent.get_next_path_position()
    var toward := next - global_position
    toward.y = 0.0
    var previous := global_position
    walk_direction(toward.normalized(), false, delta)
    var stepped := Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    travel_distance += stepped
    _no_progress = maxf(0.0, _no_progress - delta * 2.0) if stepped > .007 else _no_progress + delta
    if _no_progress >= 4.0:
        simulation.travel_failed(contestant)
        _leave()

func _close_to(p: Vector3) -> bool:
    return Vector2(p.x - global_position.x, p.z - global_position.z).length() < .83 and absf(p.y - global_position.y) < 1.05

func _leave() -> void:
    if motion_clip == &"SitDown":
        set_motion(&"StandUp")
        delay = 1.15
    else:
        set_motion(&"Idle")
        delay = .7
    target_activity = &""
    at_activity = false
    _no_progress = 0.0

func interrupt(partner: Node3D) -> void:
    talking_to = partner
    planar = Vector3.ZERO
    set_motion(&"Talk")

func resume() -> void:
    talking_to = null
    _no_progress = 0.0
    if at_activity:
        var pose: StringName = simulation.ACTIVITIES[target_activity].pose
        set_motion(&"SitDown" if pose == &"Seated" else pose)
    elif not target_activity.is_empty():
        agent.target_position = _approach
        set_motion(&"Idle")
