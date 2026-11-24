class_name TonsaiCampProps
extends Node3D

var site: TonsaiSiteData
var wood: StandardMaterial3D
var endwood: StandardMaterial3D
const LOG := preload("res://world/assets/seating_log.glb")
const ROCK := preload("res://world/assets/shore_rock.glb")
const BUCKET := preload("res://world/assets/well_bucket.glb")
const STUMP := preload("res://world/assets/seat_stump.glb")
var rock_mesh: Mesh
var rope: StandardMaterial3D
var flame: MeshInstance3D
var ember: OmniLight3D
var time := 0.0

func build(data: TonsaiSiteData) -> void:
    site = data
    wood = _material(Color("#674935"))
    endwood = _material(Color("#9e7950"))
    rope = _material(Color("#a18a61"))
    rock_mesh = _scan_mesh(ROCK)
    var fire := site.point(site.layout.landmarks.campfire)
    var ash := _material(Color("#302723"))
    _cylinder(fire + Vector3(0, -0.02, 0), fire + Vector3(0, 0.03, 0), 0.68, ash)
    for i in 12:
        var angle := TAU * i / 12.0
        var offset := Vector3(cos(angle), 0, sin(angle)) * .88
        var rock := _visual(rock_mesh, fire + offset - Vector3.UP * .025, null)
        rock.scale = Vector3(.43, .42 + .09 * sin(i * 7.8), .42)
        rock.rotation.y = i * 2.399
    for i in 5:
        var around := Vector3(cos(i * .79), 0, sin(i * .79)) * .53
        _cylinder(fire - around + Vector3.UP * .10, fire + around + Vector3.UP * .18, .075, ash)
    var fire_material := _material(Color("#ff8b30"))
    fire_material.emission_enabled = true
    fire_material.emission = Color("#ff4e13")
    fire_material.emission_energy_multiplier = 1.4
    flame = _cylinder(fire + Vector3.UP * .14, fire + Vector3.UP * .55, .22, fire_material)
    (flame.mesh as CylinderMesh).top_radius = 0.026
    for i in 3:
        var offset := Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * .17
        var tongue := _cylinder(fire + offset + Vector3.UP * .16,
            fire + offset * .8 + Vector3.UP * (.33 + i * .061), .13, fire_material)
        (tongue.mesh as CylinderMesh).top_radius = .012
    ember = OmniLight3D.new()
    ember.position = fire + Vector3.UP * .52
    ember.light_color = Color("#ff9648")
    ember.light_energy = .7
    ember.omni_range = 3.25
    add_child(ember)

    var seat_mesh := _scan_mesh(LOG)
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

func _build_well() -> void:
    var base := site.point(site.layout.landmarks.well)
    var stonework := MultiMeshInstance3D.new()
    stonework.name = "WellStonework"
    var stones := MultiMesh.new()
    stones.transform_format = MultiMesh.TRANSFORM_3D
    stones.mesh = rock_mesh
    stones.instance_count = 32
    for i in 32:
        @warning_ignore("integer_division")
        var course := i / 16
        var angle := (i % 16 + course * .5) * TAU / 16.0
        var radial := Vector3(cos(angle), 0, sin(angle))
        var yaw := -angle + PI * .5 + sin(i * 9.47) * .19
        var shape := Basis(Vector3.UP, yaw).scaled_local(Vector3(.49, .68, .48))
        var at := radial * (.88 + .026 * cos(i * 2.38)) + Vector3.UP * (.375 * course - .08)
        stones.set_instance_transform(i, Transform3D(shape, at))
    stonework.multimesh = stones
    stonework.position = base
    add_child(stonework)

    var shaft := _material(Color("#282521"))
    _cylinder(base - Vector3.UP * .04, base + Vector3.UP * .21, .73, shaft)
    # Split planked cover with the near half closed and a bucket over the opening.
    for i in 8:
        var z := .07 + i * .092
        var width := sqrt(maxf(.03, .76 ** 2 - z ** 2)) * 2.0
        _box(base + Vector3(0, .73 + .01 * sin(i), z), Vector3(width, .075, .085),
            wood if i % 3 == 0 else endwood)
    for x in [-.88, .88]:
        var post := base + Vector3(x, 0, 0)
        _cylinder(post + Vector3.UP * .05, post + Vector3.UP * 2.69, .102, wood)
        for tier in [1.88, 2.46]:
            for loop in 4:
                var lash: Vector3 = post + Vector3.UP * (tier + loop * .023)
                _cylinder(lash, lash + Vector3.UP * .020, .115, rope)
    _cylinder(base + Vector3(-1.02, 1.94, 0), base + Vector3(1.07, 1.94, 0), .077, endwood)
    for i in 7:
        var axle := base + Vector3(-.085 + i * .023, 1.94, 0)
        _cylinder(axle, axle + Vector3.RIGHT * .023, .112, rope)
    for side in [-1.0, 1.0]:
        for i in 11:
            var x := (i - 5) * .207
            var plank := _box(base + Vector3(x, 2.50, side * .41),
                Vector3(.199, .072, .96 + .04 * cos(i * 2.13)), wood if i % 3 else endwood)
            plank.rotation.x = side * .36
    _cylinder(base + Vector3(-1.17, 2.68, 0), base + Vector3(1.17, 2.68, 0), .055, wood)
    _cylinder(base + Vector3(0, 1.94, -.10), base + Vector3(0, 1.27, -.10), .022, rope)
    _visual(_scan_mesh(BUCKET), base + Vector3(0, .84, -.10), null)
    for use in [&"collection", &"conversation"]:
        var marker := Marker3D.new()
        marker.name = "Well" + String(use).capitalize()
        marker.position = site.well_anchor(use)
        add_child(marker)

func _process(delta: float) -> void:
    time += delta
    if flame != null:
        flame.scale.y = .91 + .12 * sin(time * 17.0) + .07 * cos(time * 23.0)
        ember.light_energy = .59 + .12 * sin(time * 13.0)

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
