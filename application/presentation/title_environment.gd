class_name IslandTitleEnvironment
extends Node3D

# Presentation only: no simulation, physics bodies, actors, saves or networking.
var camera := Camera3D.new()
var terrain := TonsaiTerrain.new()
var elapsed := 0.0
var economy := false

func _ready() -> void:
    var site := TonsaiSiteData.new()
    if not site.load_inputs():
        return
    terrain.site = site
    terrain.water = CampWaterSurface.new(TonsaiTerrain.SEA_LEVEL, site.height)
    add_child(terrain)
    terrain.set_process(false)
    terrain._lighting()
    terrain._land()
    terrain._sea()
    for body: Node in terrain.find_children("*", "CollisionObject3D", true, false):
        body.free()
    terrain.sun.rotation_degrees = Vector3(-42, -132, 0)
    terrain.sun.light_color = Color("#fff1d8")
    terrain.sun.light_energy = 1.05
    terrain.sun.directional_shadow_max_distance = 180
    terrain.atmosphere.ambient_light_color = Color("#c1d9ed")
    terrain.atmosphere.ambient_light_energy = .28
    terrain.atmosphere.fog_enabled = false
    var sky := Sky.new()
    sky.radiance_size = Sky.RADIANCE_SIZE_64
    var sky_material := ShaderMaterial.new()
    sky_material.shader = preload("res://application/presentation/tropical_sky.gdshader")
    sky_material.set_shader_parameter("cloud_panorama", load("res://world/assets/sunflowers-sky.jpg"))
    sky.sky_material = sky_material
    terrain.atmosphere.sky = sky
    terrain.atmosphere.sky_rotation.y = deg_to_rad(40)
    var sea := terrain.get_node("AndamanSea") as MeshInstance3D
    var ocean := sea.material_override as ShaderMaterial
    ocean.set_shader_parameter("shallows", Color("#22cbb2d9"))
    ocean.set_shader_parameter("offshore", Color("#086b9cf5"))
    ocean.set_shader_parameter("reflection_tint", Vector3(.13, .55, .73))
    ocean.set_shader_parameter("motion_strength", 1.7)
    ocean.set_shader_parameter("shimmer_strength", .65)
    var kit := TonsaiEnvironmentKit.new()
    kit.site = site
    add_child(kit)
    for source: String in ["reconstruction-low", "landmarks-low", "limestone", "palms"]:
        if not kit._load_kit(source):
            return
    # Grading must not mutate cached meshes used later by the playable camp.
    for key: String in kit.library:
        kit.library[key] = kit.library[key].duplicate() as Mesh
    kit._grade_foliage()
    for key: String in kit.library:
        if not ("leaves" in key or "crown" in key):
            continue
        var mesh := kit.library[key] as ArrayMesh
        for index in mesh.get_surface_count():
            var leaves := mesh.surface_get_material(index) as StandardMaterial3D
            if leaves != null:
                leaves.albedo_color = Color("#90b965") if "palm" in key else Color("#71974e")
    var stone := ShaderMaterial.new()
    stone.shader = TonsaiEnvironmentKit.ROCK
    stone.set_shader_parameter("limestone", load(TonsaiSiteData.DIR + "rock_06_diff_1k.jpg"))
    stone.set_shader_parameter("mineral_gain", 1.10)
    stone.set_shader_parameter("mineral_lift", .045)
    stone.set_shader_parameter("weathering", .45)
    kit._static("southern-cliff-rock-far", Vector3.ZERO, stone)
    for mass: Dictionary in site.layout.headlands:
        var cliff := kit._static("limestone-far", Vector3(mass.x, mass.y, mass.z), stone)
        cliff.rotation = Vector3(mass.tilt, mass.turn, 0)
        cliff.scale = Vector3.ONE * float(mass.s)
    for variant in 3:
        var palms: Array = kit._variant(site.layout.vegetation.palms, variant).filter(
            func(p: Array) -> bool: return p[2] > 10 and p[2] < 110)
        kit._batch(["palm-%s-far-wood" % variant, "palm-%s-far-leaves" % variant], palms, 240.0, false)
        var trees: Array = kit._variant(site.layout.vegetation.trees, variant).filter(
            func(p: Array) -> bool: return p[2] > 35 and p[2] < 120 and p[0] < 55)
        kit._batch(["forest-%s-wood-far" % variant, "forest-%s-crown-far" % variant], trees, 240.0, false)
    for visual: Node in kit.get_children():
        if visual is GeometryInstance3D:
            visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    kit.library.clear()
    add_child(camera)
    camera.fov = 62
    camera.far = 850
    camera.current = true
    set_economy(economy)
    _process(0)

func set_economy(value: bool) -> void:
    economy = value
    if terrain.sun != null:
        terrain.sun.shadow_enabled = not value

func _process(delta: float) -> void:
    elapsed += delta
    camera.position = Vector3(-78 + sin(elapsed * .075) * 3.0, 5.0, 79 + cos(elapsed * .075) * 1.5)
    camera.look_at(Vector3(10, 12, 103))
