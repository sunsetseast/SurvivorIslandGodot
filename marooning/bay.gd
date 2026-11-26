class_name MarooningBay
extends Node3D
var layout: MarooningLayout
var markers: Dictionary = {}
var wood := timber()
var bamboo := material(Color("ac9360"))
var sand := material(Color("dbcd9b"))

static func timber() -> ShaderMaterial:
    var result := ShaderMaterial.new()
    result.shader = preload("res://marooning/wood.gdshader")
    return result

static func material(color: Color) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.roughness = .88
    return result

func mark(id: String, point: Vector3) -> Marker3D:
    var marker := Marker3D.new()
    marker.name = id
    marker.position = point
    add_child(marker)
    markers[id] = marker
    return marker

func shape(id: String, mesh: Mesh, point: Vector3, surface: Material, solid := false) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = id
    node.mesh = mesh
    node.material_override = surface
    node.position = point
    add_child(node)
    if solid:
        var body := StaticBody3D.new()
        node.add_child(body)
        var collider := CollisionShape3D.new()
        collider.shape = mesh.create_convex_shape()
        body.add_child(collider)
    return node

func box(id: String, point: Vector3, size: Vector3, surface: Material, solid := true) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return shape(id, mesh, point, surface, solid)

func pole(id: String, point: Vector3, radius: float, height: float, surface: Material, solid := false) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius * .88
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    return shape(id, mesh, point, surface, solid)

func build(data: MarooningLayout, tribe_count: int) -> void:
    layout = data
    var environment := WorldEnvironment.new()
    var atmosphere := Environment.new()
    var sky := Sky.new()
    var sky_material := PanoramaSkyMaterial.new()
    sky_material.panorama = load("res://world/assets/kloofendal-clear.jpg")
    sky.sky_material = sky_material
    atmosphere.background_mode = Environment.BG_SKY
    atmosphere.sky = sky
    atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    atmosphere.ambient_light_color = Color("c0d7e1")
    atmosphere.ambient_light_energy = .65
    environment.environment = atmosphere
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -30, 0)
    sun.light_color = Color("fff1d7")
    sun.light_energy = 1.3
    add_child(sun)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for z in range(-210, 210, 5):
        for x in range(-210, 210, 5):
            for offset: Vector2 in [Vector2(0, 0), Vector2(5, 0), Vector2(0, 5), Vector2(5, 0), Vector2(5, 5), Vector2(0, 5)]:
                var point := Vector3(x + offset.x, 0, z + offset.y)
                point.y = layout.bed(point.x, point.z)
                surface.set_uv(Vector2(point.x, point.z) * .2)
                surface.add_vertex(point)
    surface.generate_normals()
    var shore_surface := ShaderMaterial.new()
    shore_surface.shader = preload("res://marooning/sand.gdshader")
    shore_surface.set_shader_parameter("sand_detail", load("res://tonsai/generated/sand_02-diff.jpg"))
    var bed_mesh := surface.commit()
    shape("BaySeabed", bed_mesh, Vector3.ZERO, shore_surface)
    var bed_body := StaticBody3D.new()
    var bed_shape := CollisionShape3D.new()
    bed_shape.shape = bed_mesh.create_trimesh_shape()
    bed_body.add_child(bed_shape)
    add_child(bed_body)
    var sea := PlaneMesh.new()
    sea.size = Vector2(1600, 1600)
    var water := ShaderMaterial.new()
    water.shader = load("res://world/water.gdshader")
    water.set_shader_parameter("ripples", load("res://world/assets/water-ripple.png"))
    shape("TropicalSea", sea, Vector3.ZERO, water)
    var stone_source: Node3D = load("res://tonsai/generated/limestone.glb").instantiate()
    var stone_parts := stone_source.find_children("*", "MeshInstance3D", true, false)
    var rock_material := ShaderMaterial.new()
    rock_material.shader = load("res://tonsai/shaders/rock.gdshader")
    rock_material.set_shader_parameter("limestone", load("res://tonsai/generated/rock_06_diff_1k.jpg"))
    for i in 5:
        var point := Vector3(-120 + i * 65, 0, 280 + (i % 2) * 40)
        if i < 2:
            point = Vector3(-66 if i == 0 else 66, 0, 193)
        for part: MeshInstance3D in stone_parts:
            var rock := shape("Limestone%d" % i, part.mesh, point, rock_material)
            rock.scale = Vector3(40, 22 + i * 2, 30) if i > 1 else Vector3(20, 12, 18)
            rock.rotation.y = i * 1.7
            rock.visibility_range_end = 650
    stone_source.free()
    _shore()
    _ship()
    for i in tribe_count:
        var mount := layout.raft_mounts[i]
        mark("raft-mount-%d" % i, mount)
        for j in 12:
            var log := pole("raft-%d-bamboo-%d" % [i, j], mount + Vector3((j - 5.5) * .31, 0, 0), .19, 7, bamboo)
            log.rotation.x = PI / 2
        for z: float in [-2.1, 0, 2.1]:
            box("raft-%d-seat" % i, mount + Vector3(0, .35, z), Vector3(3.8, .16, .5), wood)
        box("raft-%d-deck" % i, mount + Vector3(0, -.16, 0), Vector3(4, .15, 7), bamboo)
    mark("reward-dock", layout.reward)
    box("FloatingRewardDock", layout.reward, Vector3(5, .35, 5), wood)
    for x: float in [-2.2, 2.2]:
        for z: float in [-2.2, 2.2]:
            pole("DockPost", layout.reward + Vector3(x, .6, z), .11, 1.4, wood)
    mark("reward-" + layout.reward_id, layout.reward + Vector3.UP)
    box("IllustrativeFishingPackage", layout.reward + Vector3.UP * .7, Vector3(1.2, 1, .9), bamboo)
    # Matching visible access ramp lets a swimmer wade onto the stationary dock.
    var ramp := box("DockAccessRamp", layout.reward + Vector3(0, -.6, 4), Vector3(2, .15, 4), wood)
    ramp.rotation.x = .45
    mark("player-landing", layout.landing)
    mark("future-camp-transition", layout.landing + Vector3(0, 1, 16))
    for i in layout.rival_exits.size():
        mark("rival-exit-%d" % i, layout.rival_exits[i])
    pole("LandingFlagPost", layout.landing + Vector3(3, 2, 0), .08, 4, wood)
    box("LandingFlag", layout.landing + Vector3(3.7, 3.5, 0), Vector3(1.4, .7, .05), material(Color("e6c777")), false)

func _shore() -> void:
    # Reuse the existing licensed palm library without loading a camp scene.
    var path := "res://tonsai/generated/palms.glb"
    if not ResourceLoader.exists(path):
        return
    var source: Node3D = load(path).instantiate()
    var parts := source.find_children("*", "MeshInstance3D", true, false)
    for part: MeshInstance3D in parts:
        var mesh := part.mesh.duplicate() as ArrayMesh
        for surface in mesh.get_surface_count():
            var foliage := mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
            foliage.vertex_color_use_as_albedo = true
            foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
            if "leaves" in String(part.name):
                foliage.albedo_color *= Color("849856")
                foliage.metallic_specular = .08
                foliage.roughness = .97
            mesh.surface_set_material(surface, foliage)
        part.mesh = mesh
    for i in 24:
        var x := -52.0 + i * 4.5
        var z := 191.0 + sin(i * 2.3) * 5
        for part: MeshInstance3D in parts:
            if "palm-0-far" not in String(part.name):
                continue
            var tree := MeshInstance3D.new()
            tree.mesh = part.mesh
            tree.position = Vector3(x, layout.bed(x, z), z)
            tree.rotation.y = i * 2.1
            add_child(tree)
    source.free()

func _ship() -> void:
    var vessel: Node3D = load("res://marooning/assets/galleon.glb").instantiate()
    vessel.name = "MarooningShip"
    vessel.position = layout.ship_origin
    add_child(vessel)
    for node: Node in vessel.find_children("*", "Node3D", true, false):
        if "gunport" in String(node.name) or "furled" in String(node.name):
            (node as Node3D).hide()
    mark("ship", layout.ship_origin)
    mark("deck", Vector3(0, layout.deck_y, 0))
    mark("host", Vector3(0, layout.deck_y + 2.8, -11.8))
    mark("overboard-access", Vector3(4.3, layout.deck_y, 8))
    # Separate simple collision/visible circulation layer, matched to the adapted deck.
    box("OpenDeck", Vector3(0, layout.deck_y - .13, 1.5), Vector3(8, .26, 16), wood)
    box("HostPlatform", Vector3(0, layout.deck_y + 2.6, -11.5), Vector3(7.6, .4, 4), wood)
    var ramp := box("HostRamp", Vector3(-2.8, layout.deck_y + 1.35, -6.8), Vector3(1.7, .2, 6), wood)
    ramp.rotation.x = .49
    for x: float in [-4.0, 4.0]:
        box("DeckRail", Vector3(x, layout.deck_y + .6, .2), Vector3(.12, 1.2, 13.4), wood)
    var mast := StaticBody3D.new()
    mast.name = "MainMastCollision"
    mast.position = Vector3(0, layout.deck_y + 5, -3.5)
    var mast_shape := CollisionShape3D.new()
    var cylinder := CylinderShape3D.new()
    cylinder.radius = .42
    cylinder.height = 10
    mast_shape.shape = cylinder
    mast.add_child(mast_shape)
    add_child(mast)
    box("BowSafetyRail", Vector3(0, layout.deck_y + .6, 9.5), Vector3(8, 1.2, .12), wood)
    for i in 3:
        mark("spawn-group-%d" % i, Vector3(-2.4 + i * 2.4, layout.deck_y, 2))
    for i in 6:
        var point := Vector3(3.25, layout.deck_y + .4, -4 + i * 1.5)
        var id: String = ["rice-sack", "crate", "rope", "basket", "cooking-pot", "survival-kit"][i]
        mark("cargo-" + id, point)
        if id in ["rice-sack", "basket", "cooking-pot"]:
            pole(id, point, .35, .8, bamboo if id != "cooking-pot" else material(Color("414748")), true)
        elif id == "rope":
            var torus := TorusMesh.new()
            torus.inner_radius = .23
            torus.outer_radius = .4
            shape(id, torus, point, bamboo)
        else:
            box(id, point, Vector3(.8, .8, .8), bamboo)
