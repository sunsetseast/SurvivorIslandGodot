class_name MarooningPose
extends SkeletonModifier3D
## Scoped post-mixer corrections on the existing temporary rig; no rest-pose edits.
var state: Dictionary = {}
var time := 0.0
var held := false
var grips: Array[Vector3]=[]
var modification_count := 0
var grip_errors: Dictionary={}
func _process_modification_with_delta(_delta: float) -> void:
    modification_count+=1
    var skeleton := get_skeleton()
    if skeleton==null or state.is_empty(): return
    var seated: bool=state.get("place","")=="aboard"
    var stroking: bool=seated and float(state.get("power",0))>0
    var phase := clampf((time-float(state.get("stroke_at",-10)))/MarooningRace.STROKE_SECONDS,0,1)
    for side: String in ["r","l"]:
        var upper := skeleton.find_bone("upperarm_"+side)
        var lower := skeleton.find_bone("lowerarm_"+side)
        if upper<0 or lower<0: continue
        var sign_side := -1.0 if side=="r" else 1.0
        if seated and stroking and grips.size()==2:
            solve_arm(skeleton,side,grips[0 if (int(state.seat_index)%2==0)==(side=="r") else 1])
        elif held and side=="r":
            skeleton.set_bone_pose_rotation(upper,skeleton.get_bone_pose_rotation(upper)*Quaternion(Vector3.RIGHT,-.55))
            skeleton.set_bone_pose_rotation(lower,skeleton.get_bone_pose_rotation(lower)*Quaternion(Vector3.RIGHT,-.9))

func solve_arm(skeleton: Skeleton3D,side: String,target: Vector3) -> void:
    var upper := skeleton.find_bone("upperarm_"+side)
    var lower := skeleton.find_bone("lowerarm_"+side)
    var hand := skeleton.find_bone("hand_"+side)
    if mini(upper,mini(lower,hand))<0: return
    var shoulder := skeleton.get_bone_global_pose(upper)
    var elbow := skeleton.get_bone_global_pose(lower)
    var wrist := skeleton.get_bone_global_pose(hand)
    var length_a := shoulder.origin.distance_to(elbow.origin)
    var length_b := elbow.origin.distance_to(wrist.origin)
    var direction := target-shoulder.origin
    var distance := clampf(direction.length(),absf(length_a-length_b)+.001,length_a+length_b-.001)
    direction=direction.normalized()
    var bend := Vector3(0,-.3,-1)
    bend=(bend-direction*bend.dot(direction)).normalized()
    var cosine := clampf((length_a*length_a+distance*distance-length_b*length_b)/(2*length_a*distance),-1,1)
    var elbow_target := shoulder.origin+direction*length_a*cosine+bend*length_a*sqrt(maxf(0,1-cosine*cosine))
    var rotation_delta := Quaternion((elbow.origin-shoulder.origin).normalized(),(elbow_target-shoulder.origin).normalized())
    shoulder.basis=Basis(rotation_delta)*shoulder.basis
    skeleton.set_bone_global_pose(upper,shoulder)
    skeleton.force_update_all_bone_transforms()
    elbow=skeleton.get_bone_global_pose(lower)
    wrist=skeleton.get_bone_global_pose(hand)
    var reachable := shoulder.origin+direction*distance
    rotation_delta=Quaternion((wrist.origin-elbow.origin).normalized(),(reachable-elbow.origin).normalized())
    elbow.basis=Basis(rotation_delta)*elbow.basis
    skeleton.set_bone_global_pose(lower,elbow)
    skeleton.force_update_all_bone_transforms()
    grip_errors[side]=skeleton.get_bone_global_pose(hand).origin.distance_to(target)
