class_name TonsaiEnvironmentKit
extends Node3D

const ROCK := preload("res://tonsai/shaders/rock.gdshader")
const CHUNK := 34
var terrain: TonsaiTerrain
var site: TonsaiSiteData
var library: Dictionary[String, Mesh] = {}
var close_foliage: Array[MultiMeshInstance3D] = []
var sections := 0

func build(data: TonsaiSiteData, physical_world: TonsaiTerrain) -> bool:
    site = data
    terrain = physical_world
    for file_name in ["reconstruction-low", "landmarks-low", "limestone", "coastal-tree", "palms", "fern_02"]:
        if not _load_kit(file_name):
            return false
    _grade_foliage()
    var stone := ShaderMaterial.new()
    stone.shader = ROCK
    stone.set_shader_parameter("limestone", load(TonsaiSiteData.DIR + "rock_06_diff_1k.jpg"))
    for part in ["timber", "thatch", "deck", "lashings", "supplies"]:
        _static("shelter-" + part, Vector3.ZERO, null, true)
    var cliff := _static("southern-cliff-rock-far", Vector3.ZERO, stone, true)
    var cliff_shape := cliff.mesh.create_trimesh_shape()
    cliff_shape.backface_collision = true
    terrain.add_shape(cliff_shape, Vector3.ZERO, "SouthernCliff")
    for landmark: Dictionary in site.layout.naturalLandmarks + [{"id": "spring-seep", "x": 108, "z": 36}]:
        for part in ["wood", "rock"]:
            var key := "%s-%s-far" % [landmark.id, part]
            if library.has(key):
                _static(key, site.point(landmark), stone if part == "rock" else null, true)
    for mass: Dictionary in site.layout.headlands:
        var rock := _static("limestone-far", Vector3(mass.x, mass.y, mass.z), stone)
        rock.rotation = Vector3(mass.tilt, mass.turn, 0)
        rock.scale = Vector3.ONE * float(mass.s)
    var plants: Dictionary = site.layout.vegetation
    for variant in 3:
        var forest_parts := ["forest-%s-wood-far" % variant, "forest-%s-crown-far" % variant]
        _batch(forest_parts, _variant(plants.trees, variant), 135.0, false)
        _batch(["palm-%s-far-wood" % variant, "palm-%s-far-leaves" % variant],
            _variant(plants.palms, variant), 110.0, false)
        _batch(["understory-%s-leaves-far" % variant],
            _variant(plants.understory, variant), 54.0, true)
    # Keep one scanned coastal fig near the communal area for close-up bark.
    var fig := _static("coastal-trunk-far", site.ground(-19, -16), null, true)
    fig.scale = Vector3.ONE * 2.4
    for v in 4:
        _batch(["fern_02_" + ["a", "b", "c", "d"][v]], _variant(plants.ferns, v), 47.0, true)
    _batch(["limestone-far"], plants.rocks + plants.springRim, 74.0, false, true)
    terrain.add_surface(site.deck_faces(), "ShelterDeck")
    terrain.add_surface(site.ramp_faces(), "ShelterRamp")
    _obstacles()
    return true

func _load_kit(file_name: String) -> bool:
    var kit := load(TonsaiSiteData.DIR + file_name + ".glb") as PackedScene
    if kit == null:
        return false
    var scene := kit.instantiate() as Node3D
    for child in scene.find_children("*", "MeshInstance3D", true, false):
        var mesh_node := child as MeshInstance3D
        var mesh := mesh_node.mesh as ArrayMesh
        if mesh == null:
            continue
        # glTF stores color attributes for the original Three.js vertex-color
        # materials. Godot did not enable their use on these imported surfaces.
        for i in mesh.get_surface_count():
            if mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR] != null:
                var material := mesh.surface_get_material(i) as StandardMaterial3D
                material.vertex_color_use_as_albedo = true
        library[String(mesh_node.name)] = mesh
    scene.free()
    return true

func _grade_foliage() -> void:
    # The authored leaves were graded in the Three.js lighting pipeline.
    # Compatibility needs a darker albedo and less dielectric glare.
    for key: String in library:
        if not ("leaves" in key or "crown" in key or key.begins_with("fern_02")):
            continue
        var mesh := library[key] as ArrayMesh
        for i in mesh.get_surface_count():
            var material := mesh.surface_get_material(i).duplicate() as StandardMaterial3D
            material.albedo_color *= Color("#a0b66f") if key.begins_with("fern") else Color("#849856")
            material.metallic_specular = .08
            material.roughness = .97
            mesh.surface_set_material(i, material)

func _static(key: String, at: Vector3, material: Material = null, shadow := false) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = key
    node.position = at
    node.mesh = library[key]
    node.material_override = material
    if not shadow:
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node, true)
    return node

func _variant(plants: Array, variant: int) -> Array:
    return plants.filter(func(p: Array) -> bool: return int(p[5]) == variant)

func _batch(parts: Array, plants: Array, visibility: float, detail: bool, talus := false) -> void:
    var chunks: Dictionary[Vector2i, Array] = {}
    for p: Array in plants:
        var cell := Vector2i(floori(p[0] / CHUNK), floori(p[2] / CHUNK))
        if not chunks.has(cell):
            chunks[cell] = []
        var rotation := Basis(Vector3.UP, float(p[4]))
        var basis := rotation.scaled(Vector3.ONE * float(p[3]))
        if talus:
            basis = basis * Basis(Vector3.RIGHT, -PI * .5)
        chunks[cell].append(Transform3D(basis, Vector3(p[0] - cell.x * CHUNK, p[1], p[2] - cell.y * CHUNK)))
    for cell: Vector2i in chunks:
        var placements: Array = chunks[cell]
        for key: String in parts:
            if not library.has(key):
                continue
            var batch := MultiMesh.new()
            batch.transform_format = MultiMesh.TRANSFORM_3D
            batch.mesh = library[key]
            batch.instance_count = placements.size()
            for i in placements.size():
                batch.set_instance_transform(i, placements[i])
            var node := MultiMeshInstance3D.new()
            node.multimesh = batch
            node.position = Vector3(cell.x * CHUNK, 0, cell.y * CHUNK)
            node.visibility_range_end = visibility
            node.visibility_range_end_margin = 5.0
            node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            add_child(node)
            sections += 1
            if detail:
                close_foliage.append(node)

func _obstacles() -> void:
    for item: Dictionary in site.layout.colliders:
        var h := TonsaiSiteData.obstacle_height(item.kind)
        var floor_y := site.height(item.x, item.z)
        if item.kind == "post" and item.z < -40:
            h += 1.2
        var solid := StaticBody3D.new()
        solid.collision_mask = 0
        solid.position = Vector3(item.x, floor_y + h * 0.5 - 0.10, item.z)
        solid.name = String(item.kind).replace(":", "_").replace("-", "_")
        var shape := CollisionPolygon3D.new()
        shape.depth = h + 0.24
        shape.rotation.x = PI * 0.5
        var points := PackedVector2Array()
        for v in TonsaiSiteData.footprint(item):
            points.append(Vector2(v.x - item.x, v.z - item.z))
        shape.polygon = points
        solid.add_child(shape)
        add_child(solid, true)

func economy(enabled: bool) -> void:
    for node in close_foliage:
        node.visibility_range_end = 31.0 if enabled else 54.0
    terrain.sun.shadow_enabled = not enabled
