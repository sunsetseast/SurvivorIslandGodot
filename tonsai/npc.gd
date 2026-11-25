class_name TonsaiNpc
extends CampHumanoidMotor

var contestant: String
var display_name: String
var session: GameSession
var local_host: LocalGameSession
var remote: RemoteGameSession
var is_remote_human := false
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
    collision_layer = 8 if remote == null else 0
    collision_mask = 1 | 4
    super()
    if remote == null:
        _create_agent()
    else:
        set_physics_process(false)
    _create_label()

func _create_agent() -> void:
    agent = NavigationAgent3D.new()
    agent.radius = RADIUS
    agent.path_desired_distance = .55
    agent.target_desired_distance = .60
    agent.path_max_distance = 2.5
    add_child(agent)
func _create_label() -> void:
    var identifier := Label3D.new()
    identifier.text = display_name
    identifier.position.y = 1.92
    identifier.pixel_size = .0035
    identifier.font = IslandTheme.font()
    identifier.modulate = Color.WHITE
    identifier.outline_modulate = Color.BLACK
    identifier.font_size = 45
    identifier.outline_size = 5
    identifier.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    identifier.visibility_range_end = 15.0
    add_child(identifier)

func _process(_delta: float) -> void:
    if remote == null:
        return
    var frame := remote.interpolated(contestant)
    if frame.is_empty():
        return
    position = frame.position
    set_heading(frame.heading)
    var activity := remote.activity("tonsai", contestant)
    if frame.talking:
        set_motion(&"Talk")
    elif int(frame.locomotion) >= Locomotion.SWIM:
        set_motion(&"Swim" if frame.speed > .16 else &"Tread")
    elif frame.speed > .16:
        set_motion(&"Jog" if frame.speed > 2.55 else &"Walk")
    elif activity.get("stage") == "occupied" and activity.get("activity") == "shelter":
        set_motion(&"SitDown")
    else:
        set_motion(&"Idle")
    presentation.match_speed(motion_clip, frame.speed)

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
    var activity := session.activity(TonsaiCamp.LOCATION, contestant)
    var assigned := StringName(activity.get("activity", ""))
    if target_activity != assigned:
        if not target_activity.is_empty():
            _leave()
            return
        target_activity = assigned
        if not target_activity.is_empty():
            _approach = destinations[target_activity]
            agent.target_position = _approach
    if target_activity.is_empty():
        walk_direction(Vector3.ZERO, false, delta)
        return
    if activity.get("stage") == "occupied":
        walk_direction(Vector3.ZERO, false, delta, false)
        if not at_activity:
            at_activity = true
            _activity_pose()
        return
    if local_host != null and _close_to(_approach) and local_host.report_travel(contestant, String(target_activity), true):
        at_activity = true
        _activity_pose()
        return
    var next := agent.get_next_path_position()
    var toward := next - global_position
    toward.y = 0.0
    var previous := global_position
    walk_direction(toward.normalized(), false, delta)
    var stepped := Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    travel_distance += stepped
    _no_progress = maxf(0.0, _no_progress - delta * 2.0) if stepped > .007 else _no_progress + delta
    if _no_progress >= 4.0 and local_host != null and local_host.report_travel(contestant, String(target_activity), false):
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
        _activity_pose()
    elif not target_activity.is_empty():
        agent.target_position = _approach
        set_motion(&"Idle")

func _activity_pose() -> void:
    var pose: StringName = CampSimulation.ACTIVITIES[String(target_activity)].pose
    set_motion(&"SitDown" if pose == &"Seated" else pose)
