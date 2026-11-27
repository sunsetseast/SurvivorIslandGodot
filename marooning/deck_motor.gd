class_name MarooningDeckMotor
extends CampHumanoidMotor
## People remain collidable, but are never stairs or moving floor platforms.
func _ready() -> void:
    super()
    platform_floor_layers = 1 | 8
    platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
func _try_step(travel: Vector3) -> void:
    var mask := collision_mask
    collision_mask = 1
    super(travel)
    collision_mask = mask
