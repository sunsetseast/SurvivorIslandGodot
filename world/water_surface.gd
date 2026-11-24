class_name CampWaterSurface
extends RefCounted
## A horizontal water volume. The map supplies its seabed independently of rendering.

var level: float
var bed_height: Callable

func _init(surface_y: float, sample_bed: Callable) -> void:
    level = surface_y
    bed_height = sample_bed

func depth_at(point: Vector3) -> float:
    return level - float(bed_height.call(point.x, point.z))
