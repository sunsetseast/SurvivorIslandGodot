class_name MarooningPlayer
extends CampThirdPerson
## Marooning alone owns attached/transition presentation; orbit stays available.
var look_generation := 0
func orbit(relative: Vector2, viewport_space: bool) -> void:
    if not relative.is_zero_approx(): look_generation+=1
    super(relative,viewport_space)
func walk_direction(desired: Vector3, running: bool, delta: float, animate := true, dive_steer := 0.0) -> void:
    if raft_attached or locomotion_suspended:
        velocity=Vector3.ZERO
        planar=Vector3.ZERO
        return
    super(desired,running,delta,animate,dive_steer)
func _focus_height(body_y: float) -> float:
    return 1.12 if raft_attached else super(body_y)
var camera_vessel: Node3D
func _process(delta: float) -> void:
    if controller_b and is_instance_valid(camera_vessel):
        _apply_look()
        _mobile_orbit.update(camera_vessel.get_global_transform_interpolated().origin,1.4,yaw,pitch,delta,6.5,0,false)
    else: super(delta)
