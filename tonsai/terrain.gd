class_name TonsaiTerrain
extends Node3D

const GROUND := preload("res://tonsai/shaders/ground.gdshader")
const WATER := preload("res://world/water.gdshader")
const SEA_LEVEL := 0.03
const OFFSHORE_EDGE := -83.0
const TILE := 32
enum SkyPreset { CLEAR, CLOUDY, NIGHT }
const PANORAMAS := ["res://world/assets/kloofendal-clear.jpg", "res://world/assets/sunflowers-sky.jpg"]
const DAY_FOG := Color("#a8bfc4")
const NIGHT_FOG := Color("#34405c")
const WATER_FOG := Color("#206b6c")
var site: TonsaiSiteData
var sun: DirectionalLight3D
var water: CampWaterSurface
var sky_preset := SkyPreset.CLEAR
var atmosphere: Environment
var _submersion := 0.0
var _sky := Sky.new()

func build(data: TonsaiSiteData) -> void:
    site = data
    water = CampWaterSurface.new(SEA_LEVEL, site.height)
    _lighting()
    _land()
    _sea()
    _boundaries()

func _lighting() -> void:
    _sky.radiance_size = Sky.RADIANCE_SIZE_64
    _sky.process_mode = Sky.PROCESS_MODE_QUALITY
    var world := WorldEnvironment.new()
    atmosphere = Environment.new()
    world.environment = atmosphere
    atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    atmosphere.fog_enabled = true
    add_child(world)
    sun = DirectionalLight3D.new()
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    sun.directional_shadow_max_distance = 37
    sun.shadow_bias = 0.10
    sun.shadow_normal_bias = 0.8
    add_child(sun)
    set_sky_preset(SkyPreset.CLEAR)

func set_sky_preset(preset: SkyPreset) -> void:
    sky_preset = preset
    var night := preset == SkyPreset.NIGHT
    var cloudy := preset == SkyPreset.CLOUDY
    atmosphere.background_mode = Environment.BG_COLOR if night else Environment.BG_SKY
    atmosphere.background_color = Color("#151d34")
    if night:
        _sky.sky_material = null
    else:
        var panorama := PanoramaSkyMaterial.new()
        panorama.panorama = load(PANORAMAS[preset]) as Texture2D
        _sky.sky_material = panorama
    atmosphere.sky = null if night else _sky
    atmosphere.sky_rotation = Vector3(0, deg_to_rad(78.0 if cloudy else 149.0), 0)
    atmosphere.ambient_light_color = Color("#8da5d2") if night else Color("#cad5df")
    atmosphere.ambient_light_energy = .20 if night else (.47 if cloudy else .43)
    sun.rotation_degrees = Vector3(-37, -116, 0) if cloudy else Vector3(-53, -118, 0)
    sun.light_color = Color("#a7bbe9") if night else Color("#fff0da")
    sun.light_energy = .10 if night else (.84 if cloudy else .99)
    _apply_fog()

func _process(delta: float) -> void:
    var camera := get_viewport().get_camera_3d()
    if not is_instance_valid(camera):
        return
    var at := camera.global_position
    var depth := water.level - at.y if water.depth_at(at) > .08 else 0.0
    var target := smoothstep(-.05, .55, depth)
    if absf(target - _submersion) > .001:
        _submersion = lerpf(_submersion, target, 1.0 - exp(-delta * 13.0))
        _apply_fog()

func _apply_fog() -> void:
    var night := sky_preset == SkyPreset.NIGHT
    var above := NIGHT_FOG if night else DAY_FOG
    atmosphere.fog_light_color = above.lerp(WATER_FOG.darkened(.55) if night else WATER_FOG, _submersion)
    atmosphere.fog_density = lerpf(.0035 if night else .0022, .112, _submersion)
    atmosphere.fog_sky_affect = lerpf(.10, 1.0, _submersion)

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
    var mat := ShaderMaterial.new()
    mat.shader = WATER
    mat.set_shader_parameter("ripples", load("res://world/assets/water-ripple.png"))
    var ocean := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(565, 740)
    ocean.mesh = plane
    ocean.position = Vector3(-234, water.level, 18)
    ocean.material_override = mat
    ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    ocean.name = "AndamanSea"
    add_child(ocean)

func _boundaries() -> void:
    var polygon: Array = site.layout.territory
    for i in polygon.size():
        var a: Dictionary = polygon[i]
        var b: Dictionary = polygon[(i + 1) % polygon.size()]
        var edge_a := Vector2(OFFSHORE_EDGE if a.x == -70 else float(a.x), a.z)
        var edge_b := Vector2(OFFSHORE_EDGE if b.x == -70 else float(b.x), b.z)
        var label := "OffshoreLimit" if edge_a.x == edge_b.x and edge_a.x == OFFSHORE_EDGE else "TerritoryEdge"
        _wall(edge_a, edge_b, label)

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
