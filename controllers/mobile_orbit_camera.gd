extends RefCounted
## Render-frame third-person rig. Physics owns the body; this rig samples
## its interpolated pose and applies exactly one camera transform per frame.

const Damp := preload("res://controllers/third_party/phantom_damping.gd")
const ORBIT_DAMP_TIME := .060
const RECOVERY_DELAY := .075
const WALL_MARGIN := .075

var rendered_yaw := 0.0
var rendered_pitch := 0.0
var obstructed := false
var distance := 4.25
var _pitch := 0.0
var _height := 1.43
var _recovery := 0.0
var _yaw_damping := Damp.new()
var _pitch_damping := Damp.new()
var _probe := ShapeCast3D.new()
var _pivot: Node3D
var _camera: Camera3D

func setup(pivot: Node3D, camera: Camera3D, nominal_distance: float) -> void:
    _pivot = pivot
    _camera = camera
    var sphere := SphereShape3D.new()
    sphere.radius = .24
    _probe.shape = sphere
    _probe.enabled = false
    _probe.collision_mask = 1
    _probe.max_results = 1
    _probe.target_position = Vector3.BACK * nominal_distance
    _pivot.add_child(_probe)

func sync(yaw: float, pitch: float, focus_height: float, boom: float) -> void:
    rendered_yaw = yaw
    rendered_pitch = pitch
    _pitch = pitch
    _height = focus_height
    _yaw_damping.velocity = 0.0
    _pitch_damping.velocity = 0.0
    distance = boom
    obstructed = false
    _recovery = 0.0

func update(body_position: Vector3, focus_height: float, yaw: float, pitch: float, delta: float,
        nominal_distance: float, surface_level: float, submerged: bool) -> void:
    _height = lerpf(_height, focus_height, 1.0 - exp(-delta * 12.0))
    var focus := body_position + Vector3.UP * _height
    rendered_yaw = _yaw_damping.step(rendered_yaw, yaw, ORBIT_DAMP_TIME, delta)
    _pitch = _pitch_damping.step(_pitch, pitch, ORBIT_DAMP_TIME, delta)
    rendered_pitch = _pitch
    if surface_level != -INF:
        var clearance := focus.y - surface_level - .21
        if submerged:
            # Keep the default orbit below the surface once the focus dives.
            if focus.y < surface_level:
                var waterline_pitch := asin(clampf((focus.y - surface_level + .10) / nominal_distance, -.9, .70))
                rendered_pitch = maxf(_pitch, waterline_pitch)
        else:
            rendered_pitch = minf(_pitch, asin(clampf(clearance / nominal_distance, -.2, .42)))

    _pivot.global_transform = Transform3D(Basis.from_euler(Vector3(rendered_pitch, rendered_yaw, 0)), focus)

    # As in Phantom Camera's third-person follow, force a sweep from this
    # frame's interpolated focus. A physics-tick cache can miss the current ray.
    _probe.force_shapecast_update()
    var limit := nominal_distance
    if _probe.is_colliding():
        limit = maxf(0.0, _probe.get_closest_collision_safe_fraction() * nominal_distance - WALL_MARGIN)
    if obstructed and limit >= nominal_distance:
        _recovery = RECOVERY_DELAY
    obstructed = limit < nominal_distance
    if limit < distance:
        distance = limit
        _recovery = RECOVERY_DELAY
    elif _recovery > 0.0:
        _recovery -= delta
    else:
        distance = minf(limit, lerpf(distance, limit, 1.0 - exp(-delta * 6.0)))
    _camera.position.z = distance
