class_name TonsaiCampProps
extends Node3D

var site: TonsaiSiteData
var wood: StandardMaterial3D
var endwood: StandardMaterial3D
const LOG := preload("res://world/assets/seating_log.glb")
const ROCK := preload("res://world/assets/shore_rock.glb")
const STUMP := preload("res://world/assets/seat_stump.glb")
var rock_mesh: Mesh
var campfire: CampFire
var well_lid: Node3D
var well_scoop: Node3D

func build(data: TonsaiSiteData) -> void:
    site = data
    wood = _material(Color("#674935"))
    endwood = _material(Color("#9e7950"))
    rock_mesh = _scan_mesh(ROCK)
    var seat_mesh := _scan_mesh(LOG)
    _build_fire(site.point(site.layout.landmarks.campfire), seat_mesh)
    for entry: Dictionary in site.layout.logs:
        var node := _visual(seat_mesh, site.point(entry) - Vector3.UP * .05, null)
        node.scale.x = float(entry.len)
        node.rotation.y = -float(entry.yaw)
    _visual(_scan_mesh(STUMP), site.ground(-11.65, -34.1) - Vector3.UP * .36, null)

    var props: Dictionary = site.layout.props
    var rack_a := site.point(props.rack[0])
    var rack_b := site.point(props.rack[1])
    for base in [rack_a, rack_b]:
        _cylinder(base, base + Vector3.UP * 1.78, .068, wood)
    _cylinder(rack_a + Vector3.UP * 1.67, rack_b + Vector3.UP * 1.67, .055, endwood)
    for i in 11:
        var p := rack_a.lerp(rack_b, float(i) / 10.0) + Vector3.UP * 1.42
        _cylinder(p + Vector3.LEFT * .53, p + Vector3.RIGHT * .53, .032, wood)
    var crate := site.point(props.crates)
    for i in 4:
        _box(crate + Vector3(0, .105 + .115 * i, 0), Vector3(.94, .10, .76), wood if i % 2 else endwood)
    for x in [-.43, .43]:
        _box(crate + Vector3(x, .49, 0), Vector3(.085, .08, .85), wood)
    var barrel := site.point(props.barrel)
    _cylinder(barrel, barrel + Vector3.UP * .76, .39, endwood)
    for h in [.13, .64]:
        _cylinder(barrel + Vector3.UP * h, barrel + Vector3.UP * (h + .048), .405, wood)
    # Visual ramp treads follow the exact authored ramp surface. One continuous
    # collider underneath gives the player and NPCs reliable footing.
    var ramp: Dictionary = site.layout.shelter.ramp
    for i in 20:
        var ratio := (i + .5) / 20.0
        var z := lerpf(ramp.z1, ramp.z0, ratio)
        var y := lerpf(site.height(12, ramp.z1), float(site.layout.shelter.deck.y), ratio)
        _box(Vector3(12, y - .04, z), Vector3(4, .08, .326), wood if i % 4 == 1 else endwood)

    _build_well()

    for entry: Dictionary in props.signs:
        var p := site.point(entry)
        _cylinder(p, p + Vector3.UP * 1.47, .058, wood)
        var marker := _box(p + Vector3.UP * 1.37, Vector3(1.48, .26, .075), wood)
        marker.rotation.y = float(entry.yaw)
        var label := Label3D.new()
        label.text = entry.text
        label.font_size = 45
        label.pixel_size = .0042
        label.outline_size = 2
        label.position.z = .041
        marker.add_child(label)

func _scan_mesh(scene: PackedScene) -> Mesh:
    var instance := scene.instantiate()
    var mesh := instance.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
    var result := mesh.mesh
    instance.free()
    return result

func _build_fire(at: Vector3, log_mesh: Mesh) -> void:
    var ash := _material(Color("#292422"))
    _cylinder(at - Vector3.UP * .02, at + Vector3.UP * .04, .70, ash)
    for i in 11:
        var angle := TAU * i / 11.0 + .068 * sin(i * 8.1)
        var offset := Vector3(cos(angle), 0, sin(angle)) * (.81 + .074 * cos(i * 3.4))
        var rock := _visual(rock_mesh, at + offset - Vector3.UP * .036, null)
        rock.scale = Vector3(.43 + .08 * cos(i * 6.0), .35 + .16 * absf(sin(i * 7.8)), .43)
        rock.rotation.y = i * 2.399
    var charcoal := (log_mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
    charcoal.albedo_color = Color("#544744")
    for i in 5:
        var angle := i * 1.256
        var radial := Vector3(cos(angle), 0, sin(angle))
        var log_piece := _visual(log_mesh, at + radial * .25 + Vector3.UP * (.065 + .027 * (i % 2)), charcoal)
        log_piece.scale = Vector3(.69, .34, .31)
        log_piece.rotation = Vector3(0, -angle, -.20)
    var coals := _material(Color("#421e14"))
    coals.emission_enabled = true
    coals.emission = Color("#bf360b")
    coals.emission_energy_multiplier = .35
    for i in 7:
        var angle := i * 2.399
        var coal := _visual(rock_mesh, at + Vector3(cos(angle), .046, sin(angle)) * .45, coals)
        coal.scale = Vector3(.144, .11, .12)
        coal.rotation.y = angle
    campfire = CampFire.new()
    campfire.position = at + Vector3.UP * .14
    add_child(campfire)

func _build_well() -> void:
    var base := site.point(site.layout.landmarks.well)
    var stonework := MultiMeshInstance3D.new()
    stonework.name = "WellStonework"
    var stones := MultiMesh.new()
    stones.transform_format = MultiMesh.TRANSFORM_3D
    stones.mesh = rock_mesh
    stones.instance_count = 48
    for i in 48:
        @warning_ignore("integer_division")
        var course := i / 16
        var angle := (i % 16 + course * .5) * TAU / 16.0
        var radial := Vector3(cos(angle), 0, sin(angle))
        var yaw := -angle + PI * .5 + sin(i * 9.47) * .19
        var shape := Basis(Vector3.UP, yaw).scaled_local(Vector3(.46, .49, .43))
        var at := radial * (.89 + .026 * cos(i * 2.38)) + Vector3.UP * (.285 * course - .12)
        stones.set_instance_transform(i, Transform3D(shape, at))
    stonework.multimesh = stones
    stonework.position = base
    add_child(stonework)

    var clay := _material(Color("#77503c"))
    var gold := _material(Color("#ac8356"))
    _ring(base + Vector3.UP * .83, .73, 1.03, clay)
    _ring(base + Vector3.UP * .69, .95, 1.06, gold)
    # Repeated lozenges recall the geometric borders on Thai earthenware.
    for i in 12:
        var angle := TAU * i / 12.0
        var radial := Vector3(cos(angle), 0, sin(angle))
        var motif := _box(base + radial * 1.036 + Vector3.UP * .73, Vector3(.10, .10, .035), clay)
        motif.basis = Basis(Vector3.UP, PI * .5 - angle) * Basis(Vector3.BACK, PI * .25)
    var reservoir := _material(Color("#246563"))
    reservoir.roughness = .22
    _cylinder(base + Vector3.UP * .51, base + Vector3.UP * .53, .76, reservoir)

    well_lid = Node3D.new()
    well_lid.name = "WellLid"
    well_lid.position = base + Vector3(.17, .98, .02)
    add_child(well_lid)
    var lid := _cylinder(well_lid.position - Vector3.UP * .061, well_lid.position, .82, endwood)
    (lid.mesh as CylinderMesh).radial_segments = 32
    lid.reparent(well_lid)
    for i in range(-4, 5):
        var z := i * .16
        var chord := sqrt(.80 * .80 - z * z) * 2.0
        _box(well_lid.position + Vector3(0, .001, z), Vector3(chord, .006, .009), wood).reparent(well_lid)
    for x in [-.40, .40]:
        _box(well_lid.position + Vector3(x, .032, 0), Vector3(.075, .060, 1.18), wood).reparent(well_lid)
    var grip := _material(Color("#382f25"))
    for x in [-.14, .14]:
        _cylinder(well_lid.position + Vector3(x, 0, 0), well_lid.position + Vector3(x, .13, 0), .025, grip).reparent(well_lid)
    _cylinder(well_lid.position + Vector3(-.14, .13, 0), well_lid.position + Vector3(.14, .13, 0), .025, grip).reparent(well_lid)

    well_scoop = Node3D.new()
    well_scoop.name = "WellScoop"
    well_scoop.position = base + Vector3(-.21, 1.065, -.36)
    add_child(well_scoop)
    var handle := well_scoop.position
    _cylinder(handle + Vector3(-.57, 0, .11), handle + Vector3(.65, 0, -.18), .027, wood).reparent(well_scoop)
    var bowl := handle + Vector3(.68, -.02, -.185)
    var cup := _cylinder(bowl, bowl + Vector3.UP * .051, .127, grip)
    (cup.mesh as CylinderMesh).bottom_radius = .077
    cup.reparent(well_scoop)
    _ring(bowl + Vector3.UP * .056, .104, .139, gold).reparent(well_scoop)
    for use in [&"collection", &"conversation"]:
        var marker := Marker3D.new()
        marker.name = "Well" + String(use).capitalize()
        marker.position = site.well_anchor(use)
        add_child(marker)

func _ring(at: Vector3, inner: float, outer: float, material: Material) -> MeshInstance3D:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner
    mesh.outer_radius = outer
    mesh.rings = 32
    mesh.ring_segments = 8
    return _visual(mesh, at, material)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = .94
    return material

func _visual(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.position = at
    node.material_override = material
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)
    return node

func _box(at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    return _visual(mesh, at, material)

func _cylinder(a: Vector3, b: Vector3, width: float, material: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = width
    mesh.bottom_radius = width
    mesh.height = a.distance_to(b)
    mesh.radial_segments = 10
    mesh.rings = 0
    var node := _visual(mesh, (a + b) * .5, material)
    node.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
    return node
