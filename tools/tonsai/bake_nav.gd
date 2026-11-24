extends SceneTree

func _initialize() -> void:
    var site := TonsaiSiteData.new()
    if not site.load_inputs():
        push_error("Run tools/tonsai/prepare.mjs before baking Tonsai navigation.")
        quit(1)
        return
    var mesh := NavigationMesh.new()
    mesh.cell_size = 0.20
    mesh.cell_height = 0.10
    mesh.agent_radius = 0.40
    mesh.agent_height = 1.8
    mesh.agent_max_climb = 0.30
    mesh.agent_max_slope = 40.0
    mesh.region_min_size = 3.0
    NavigationServer3D.bake_from_source_geometry_data(mesh, site.navigation_source())
    if mesh.get_polygon_count() < 100 or ResourceSaver.save(mesh, TonsaiSiteData.DIR + "navigation.res") != OK:
        push_error("Tonsai navigation bake is empty or could not be saved.")
        quit(1)
        return
    print("Tonsai navigation baked offline: ", mesh.get_polygon_count(), " polygons")
    quit()
