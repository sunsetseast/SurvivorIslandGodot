extends CampPhysicalMotor

var human := false
var agent: NavigationAgent3D
var activity := ""
var stalled := 0.0
var delay := 0.0
var last_input := {}
var received_at := 0
var applied := 0

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1 | 4
    super()
    if not human:
        agent = NavigationAgent3D.new()
        agent.radius = RADIUS
        agent.path_desired_distance = .55
        agent.target_desired_distance = .60
        agent.path_max_distance = 2.5
        add_child(agent)

func clear_input() -> void:
    last_input = {}
    applied = 0
    planar = Vector3.ZERO

func drive(delta: float, partner: Node3D) -> void:
    if partner != null:
        planar = Vector3.ZERO
        walk_direction(Vector3.ZERO, false, delta)
        face_point(partner.global_position, delta)
        return
    if last_input.is_empty() or Time.get_ticks_msec() - received_at > 300:
        walk_direction(Vector3.ZERO, false, delta)
        return
    if not last_input.dive:
        dive_requested = false
    elif not dive_requested and can_dive():
        toggle_dive()
    walk_direction(Vector3(last_input.x, 0, last_input.z), last_input.run, delta, false, last_input.vertical)
    applied = int(last_input.seq)

func follow(assignment: Dictionary, destination: Vector3, delta: float, partner: Node3D) -> int:
    if partner != null:
        walk_direction(Vector3.ZERO, false, delta)
        face_point(partner.global_position, delta)
        return 0
    if delay > 0.0:
        delay -= delta
        walk_direction(Vector3.ZERO, false, delta)
        return 0
    if activity != assignment.activity:
        activity = assignment.activity
        stalled = 0.0
        if not activity.is_empty():
            agent.target_position = destination
    if assignment.stage != "travel" or NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
        walk_direction(Vector3.ZERO, false, delta)
        return 0
    var separation := destination - position
    if Vector2(separation.x, separation.z).length() < .83 and absf(separation.y) < 1.05:
        return 1
    var offset := agent.get_next_path_position() - position
    offset.y = 0.0
    var previous := position
    walk_direction(offset.normalized(), false, delta)
    stalled = stalled + delta if previous.distance_squared_to(position) < .00005 else maxf(0.0, stalled - delta)
    return -1 if stalled >= 4.0 else 0

func _steer_planar(input: Vector3, speed: float, acceleration: float, braking: float, delta: float) -> void:
    if human:
        steer_player(input, speed, acceleration, braking, delta)
    else:
        super(input, speed, acceleration, braking, delta)
