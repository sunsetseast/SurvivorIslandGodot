extends RefCounted
## Scalar SmoothDamp adapted from Phantom Camera's phantom_camera_3d.gd.
## Copyright (c) 2022 Marcus Skov. See PHANTOM_CAMERA_LICENSE.txt.
## Upstream revision 7945af6b16443b0ec901095d24b6863a59b7cd74.

var velocity := 0.0

func step(current: float, target: float, damping_time: float, delta: float) -> float:
    if delta <= 0.0:
        return current
    var omega := 2.0 / maxf(.0001, damping_time)
    var x := omega * delta
    var exponential := 1.0 / (1.0 + x + .48 * x * x + .235 * x * x * x)
    var difference := current - target
    var temp := (velocity + omega * difference) * delta
    velocity = (velocity - omega * temp) * exponential
    var output := target + (difference + temp) * exponential
    # Clamp against the target on a change of direction, as upstream does.
    if (target - current > 0.0) == (output > target):
        velocity = 0.0
        return target
    return output
