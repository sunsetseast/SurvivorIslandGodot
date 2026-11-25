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
    terrain.sun.rotation_degrees = Vector3(-24, -118, 0)
    terrain.sun.light_color = Color("#ffe5be")
    terrain.sun.light_energy = .85
    terrain.atmosphere.ambient_light_color = Color("#c4d4cf")
    terrain.atmosphere.ambient_light_energy = .48
    terrain.atmosphere.fog_light_color = Color("#d7c6aa")
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
    var stone := ShaderMaterial.new()
    stone.shader = TonsaiEnvironmentKit.ROCK
    stone.set_shader_parameter("limestone", load(TonsaiSiteData.DIR + "rock_06_diff_1k.jpg"))
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
    camera.position = Vector3(-78 + sin(elapsed * .045) * 1.2, 5.0, 79 + cos(elapsed * .045) * .8)
    camera.look_at(Vector3(10, 12, 103))
