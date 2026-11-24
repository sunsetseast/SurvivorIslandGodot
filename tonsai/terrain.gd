class_name TonsaiTerrain
extends Node3D

const GROUND := preload("res://tonsai/shaders/ground.gdshader")
const WATER := preload("res://tonsai/shaders/water.gdshader")
const SKY := preload("res://tonsai/shaders/sky.gdshader")
const TILE := 32
var site: TonsaiSiteData
var sun: DirectionalLight3D

func build(data: TonsaiSiteData) -> void:
    site = data
    _lighting()
    _land()
    _sea()
    _boundaries()

func _lighting() -> void:
    var sky_mat := ShaderMaterial.new()
    sky_mat.shader = SKY
    sky_mat.set_shader_parameter("clouds", load(TonsaiSiteData.DIR + "tropical-clouds.png"))
    var sky := Sky.new()
    sky.sky_material = sky_mat
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    var env := world.environment
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#bbd7e7")
    env.ambient_light_energy = 0.59
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#b4cfcc")
    env.fog_density = 0.003
    add_child(world)
    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-37, -116, 0)
    sun.light_energy = 1.02
    sun.light_color = Color("#fff0cc")
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    sun.directional_shadow_max_distance = 37
    sun.shadow_bias = 0.10
    sun.shadow_normal_bias = 0.8
    add_child(sun)

func _land() -> void:
    var material := ShaderMaterial.new()
    material.shader = GROUND
    material.set_shader_parameter("sand", load(TonsaiSiteData.DIR + "sand_02-diff.jpg"))
    material.set_shader_parameter("litter", load(TonsaiSiteData.DIR + "brown_mud_leaves_01-diff.jpg"))
    for z in range(0, site.size.y - 1, TILE):
        for x in range(0, site.size.x - 1, TILE):
            var node := MeshInstance3D.new()
            node.mesh = _tile(x, z, mini(x + TILE, site.size.x - 1), mini(z + TILE, site.size.y - 1))
            node.material_override = material
            node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            node.name = "Ground_%s_%s" % [x, z]
            add_child(node)
    var ground := HeightMapShape3D.new()
    ground.map_width = site.size.x
    ground.map_depth = site.size.y
    ground.map_data = site.heights
    add_shape(ground, Vector3(site.origin.x + (site.size.x - 1) * 0.5, 0.0,
        site.origin.y + (site.size.y - 1) * 0.5), "Heightfield")

func _tile(x0: int, z0: int, x1: int, z1: int) -> ArrayMesh:
    var points := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    var stride := x1 - x0 + 1
    for z in range(z0, z1 + 1):
        for x in range(x0, x1 + 1):
            points.append(Vector3(x + site.origin.x, site.sample(x, z), z + site.origin.y))
            normals.append(Vector3(site.sample(x - 1, z) - site.sample(x + 1, z), 2.0,
                site.sample(x, z - 1) - site.sample(x, z + 1)).normalized())
            var i := (z * site.size.x + x) * 9 + 4
            colors.append(Color8(site.raster[i], site.raster[i + 1], site.raster[i + 2], site.raster[i + 4]))
    for z in range(z1 - z0):
        for x in range(x1 - x0):
            var i := z * stride + x
            indices.append_array(PackedInt32Array([i, i + 1, i + stride, i + 1, i + stride + 1, i + stride]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = points
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _sea() -> void:
    var shores := PackedFloat32Array(site.layout.shore)
    var coast := Image.create_from_data(shores.size(), 1, false, Image.FORMAT_RF, shores.to_byte_array())
    var mat := ShaderMaterial.new()
    mat.shader = WATER
    mat.set_shader_parameter("coast", ImageTexture.create_from_image(coast))
    var ocean := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(565, 740)
    ocean.mesh = plane
    ocean.position = Vector3(-234, 0.03, 18)
    ocean.material_override = mat
    ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    ocean.name = "AndamanSea"
    add_child(ocean)

func _boundaries() -> void:
    var polygon: Array = site.layout.territory
    for i in polygon.size():
        _wall(Vector2(polygon[i].x, polygon[i].z), Vector2(polygon[(i + 1) % polygon.size()].x,
            polygon[(i + 1) % polygon.size()].z), "TerritoryEdge")
    var shores: Array = site.layout.shore
    for i in range(0, shores.size() - 1, 3):
        var j := mini(i + 3, shores.size() - 1)
        _wall(Vector2(float(shores[i]) - 0.55, site.origin.y + i),
            Vector2(float(shores[j]) - 0.55, site.origin.y + j), "Shallows")

func _wall(a: Vector2, b: Vector2, label: String) -> void:
    var edge := b - a
    var mid := (a + b) * 0.5
    var shape := BoxShape3D.new()
    shape.size = Vector3(edge.length() + 0.2, 26, 0.30)
    var wall := add_shape(shape, Vector3(mid.x, 6, mid.y), label, 4)
    wall.rotation.y = -edge.angle()

func add_shape(shape: Shape3D, at: Vector3, label: String, layer := 1) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = label
    body.position = at
    body.collision_layer = layer
    body.collision_mask = 0
    var collider := CollisionShape3D.new()
    collider.shape = shape
    body.add_child(collider)
    add_child(body, true)
    return body

func add_surface(faces: PackedVector3Array, label: String) -> void:
    var shape := ConcavePolygonShape3D.new()
    shape.backface_collision = true
    shape.set_faces(faces)
    add_shape(shape, Vector3.ZERO, label)
