class_name TonsaiSiteData
extends RefCounted

const DIR := "res://tonsai/generated/"
var layout: Dictionary
var heights := PackedFloat32Array()
var raster := PackedByteArray()
var origin := Vector2i.ZERO
var size := Vector2i.ZERO

func load_inputs() -> bool:
    var input := FileAccess.get_file_as_string(DIR + "layout.json")
    if input.is_empty():
        return false
    layout = JSON.parse_string(input)
    var extent: Dictionary = layout.extent
    origin = Vector2i(extent.minX, extent.minZ)
    size = Vector2i(int(extent.maxX) - origin.x + 1, int(extent.maxZ) - origin.y + 1)
    raster = FileAccess.get_file_as_bytes(DIR + "heightfield.bin")
    if raster.size() != size.x * size.y * 9:
        return false
    heights.resize(size.x * size.y)
    for i in heights.size():
        heights[i] = raster.decode_float(i * 9)
    return true

func sample(x: int, z: int) -> float:
    return heights[clampi(z, 0, size.y - 1) * size.x + clampi(x, 0, size.x - 1)]

func height(x: float, z: float) -> float:
    var local := Vector2(x, z) - Vector2(origin)
    var i := Vector2i(local.floor())
    var f := local - Vector2(i)
    # HeightMapShape3D triangulates each cell. This interpolation also matches
    # the terrain around the camp pads and the hand-built ramp.
    return lerpf(lerpf(sample(i.x, i.y), sample(i.x + 1, i.y), f.x),
        lerpf(sample(i.x, i.y + 1), sample(i.x + 1, i.y + 1), f.x), f.y)

func ground(x: float, z: float) -> Vector3:
    return Vector3(x, height(x, z), z)

func point(record: Dictionary) -> Vector3:
    return ground(float(record.x), float(record.z))

func well_anchor(use: StringName) -> Vector3:
    return point(layout.wellAnchors[String(use)])

func deck_faces() -> PackedVector3Array:
    var deck: Dictionary = layout.shelter.deck
    return quad(Vector3(deck.x0, deck.y, deck.z0), Vector3(deck.x1, deck.y, deck.z0),
        Vector3(deck.x0, deck.y, deck.z1), Vector3(deck.x1, deck.y, deck.z1))

func ramp_faces() -> PackedVector3Array:
    var ramp: Dictionary = layout.shelter.ramp
    var top: float = layout.shelter.deck.y
    return quad(Vector3(ramp.x0, top, ramp.z0), Vector3(ramp.x1, top, ramp.z0),
        ground(ramp.x0, ramp.z1), ground(ramp.x1, ramp.z1))

static func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector3Array:
    return PackedVector3Array([a, b, c, b, d, c])

func navigation_source() -> NavigationMeshSourceGeometryData3D:
    var source := NavigationMeshSourceGeometryData3D.new()
    var faces := PackedVector3Array()
    for z in range(size.y - 1):
        for x in range(size.x - 1):
            var i := (z * size.x + x) * 9 + 7
            if not (raster[i] and raster[i + 9] and raster[i + size.x * 9] and raster[i + size.x * 9 + 9]):
                continue
            var wx := x + origin.x
            var wz := z + origin.y
            # Remove the covered ground band so the navmesh routes via the ramp.
            if wx >= 7 and wx < 17 and wz >= -48 and wz < -40:
                continue
            if wx >= 10 and wx < 14 and wz >= -40 and wz < -33:
                continue
            faces.append_array(quad(Vector3(wx, sample(x, z), wz), Vector3(wx + 1, sample(x + 1, z), wz),
                Vector3(wx, sample(x, z + 1), wz + 1), Vector3(wx + 1, sample(x + 1, z + 1), wz + 1)))
    faces.append_array(deck_faces())
    faces.append_array(ramp_faces())
    source.add_faces(faces, Transform3D.IDENTITY)
    for item: Dictionary in layout.colliders:
        var polygon := footprint(item)
        var base := height(item.x, item.z) - 0.5
        if item.kind == "post" and item.z < -40:
            base = 1.0
        # Reserve a small voxelization and corridor-following margin in
        # addition to the agent radius. Thin angled hulls can otherwise leave
        # a valid path corner inside a body-sized collision shape.
        var outline := PackedVector2Array()
        for point in polygon:
            outline.append(Vector2(point.x, point.z))
        var padded := Geometry2D.offset_polygon(outline, .34, Geometry2D.JOIN_ROUND)
        for surface: PackedVector2Array in padded:
            var volume := PackedVector3Array()
            for point in surface:
                volume.append(Vector3(point.x, 0, point.y))
            source.add_projected_obstruction(volume, base, obstacle_height(item.kind) + .5, false)
    return source

static func footprint(item: Dictionary) -> PackedVector3Array:
    var polygon := PackedVector3Array()
    for vertex: Array in item.get("polygon", []):
        polygon.append(Vector3(vertex[0], 0.0, vertex[1]))
    if polygon.is_empty():
        var x: float = item.x
        var z: float = item.z
        var a: float = item.hx
        var b: float = item.hz
        if item.kind in ["tree", "palm", "rock", "well"]:
            for i in 8:
                var angle := TAU * i / 8.0
                polygon.append(Vector3(x + cos(angle) * a, 0.0, z + sin(angle) * b))
        else:
            polygon = PackedVector3Array([Vector3(x - a, 0, z - b), Vector3(x + a, 0, z - b),
                Vector3(x + a, 0, z + b), Vector3(x - a, 0, z + b)])
    return polygon

static func obstacle_height(kind: String) -> float:
    if kind in ["tree", "palm", "post"] or kind.begins_with("landmark:"):
        return 4.6
    if kind.begins_with("root:"):
        return 0.55
    if kind == "well":
        return 2.6
    return 0.55 if kind in ["log", "fire", "driftwood"] else 1.2
