extends SceneTree
func _initialize() -> void:
    call_deferred("bake")
func bake() -> void:
    var bay := MarooningBay.new()
    root.add_child(bay)
    bay.build(load("res://marooning/layout.tres"), 3)
    var mesh := NavigationMesh.new()
    mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
    mesh.agent_radius = .4
    mesh.agent_height = 1.8
    mesh.cell_size = .25
    mesh.cell_height = .15
    # Only deck circulation: exclude seabed, interior hull and distant platforms.
    mesh.filter_baking_aabb = AABB(Vector3(-3.8, 1.5, -9.5), Vector3(7.6, 6.0, 19))
    var source := NavigationMeshSourceGeometryData3D.new()
    NavigationServer3D.parse_source_geometry_data(mesh, source, bay)
    NavigationServer3D.bake_from_source_geometry_data(mesh, source)
    var result := ResourceSaver.save(mesh, "res://marooning/navigation.res")
    print("Marooning navigation: ", mesh.get_polygon_count(), " polygons; save ", result)
    quit(result)
