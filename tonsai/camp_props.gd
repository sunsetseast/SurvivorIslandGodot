class_name TonsaiCampProps
extends Node3D

var site: TonsaiSiteData
var wood: StandardMaterial3D
var endwood: StandardMaterial3D
var stone: StandardMaterial3D
var flame: MeshInstance3D
var ember: OmniLight3D
var time := 0.0

func build(data: TonsaiSiteData) -> void:
    site = data
    wood = _material(Color("#674935"))
    endwood = _material(Color("#9e7950"))
    stone = _material(Color("#969388"))
    var fire := site.point(site.layout.landmarks.campfire)
    var ash := _material(Color("#302723"))
    _cylinder(fire + Vector3(0, -0.02, 0), fire + Vector3(0, 0.03, 0), 0.68, ash)
    for i in 13:
        var angle := TAU * i / 13.0
        var place := fire + Vector3(cos(angle), 0.11, sin(angle)) * 0.87
        var rock := SphereMesh.new()
        rock.radial_segments = 7
        rock.rings = 3
        rock.radius = .19 + .035 * sin(i * 7.8)
        rock.height = .26 + .08 * cos(i * 2.5)
        var node := _visual(rock, place, stone)
        node.rotation.y = i * 1.92
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

    for entry: Dictionary in site.layout.logs:
        var p := site.point(entry) + Vector3.UP * .23
        var axis := Vector3(cos(entry.yaw), 0, sin(entry.yaw)) * float(entry.len) * .5
        _cylinder(p - axis, p + axis, .245, wood)
        var end := axis.normalized() * .018
        _cylinder(p - axis - end, p - axis, .218, endwood)
        _cylinder(p + axis, p + axis + end, .218, endwood)

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

    var pool := site.point(site.layout.landmarks.well)
    var water := _material(Color("#458d78"))
    water.roughness = .32
    var surface := _cylinder(pool - Vector3.UP * .09, pool + Vector3.UP * .035, 1.49, water)
    surface.scale.z = .80
    var trough := site.point(props.trough)
    _box(trough + Vector3.UP * .25, Vector3(1.6, .45, .63), wood)
    _box(trough + Vector3.UP * .49, Vector3(1.43, .025, .44), water)

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
