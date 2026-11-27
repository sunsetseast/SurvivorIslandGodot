extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var catalog := SurvivorContestantCatalog.new()
    if not catalog.available: catalog=load("res://tests/marooning_test.gd").fixture()
    for count_value in [2,3]:
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id=18
        var division := SurvivorSeasonConfiguration.new()
        division.count=count_value
        division.assign(catalog)
        var preview := MarooningPreview.new()
        preview.catalog=catalog
        preview.configuration=division.configuration(catalog,setup)
        root.add_child(preview)
        await process_frame
        for frame in 3: await physics_frame
        var space := preview.get_world_3d().direct_space_state
        var map: RID=preview.scramble.agents.values()[0].get_navigation_map()
        var capsule := CapsuleShape3D.new()
        capsule.radius=CampPhysicalMotor.RADIUS
        capsule.height=1.69
        var counts := {}
        for item: Dictionary in preview.scramble.simulation.items.values():
            var approaches: Array[Vector3] = []
            for index in 8:
                var angle := index*TAU/8.0
                var point: Vector3=item.position+Vector3(sin(angle),0,cos(angle))
                var nav := NavigationServer3D.map_get_closest_point(map,point)
                if MarooningDeckTraffic.planar(nav,point)>.4: continue
                var path := NavigationServer3D.map_get_path(map,Vector3(0,preview.layout.deck_y,7),nav,true)
                if path.is_empty(): continue
                var down := PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point-Vector3.UP,1)
                var floor_hit := space.intersect_ray(down)
                if floor_hit.is_empty(): continue
                var feet: Vector3=floor_hit.position+Vector3.UP*.02
                if absf(nav.y-feet.y)>.45 or feet.distance_to(item.position)>1.75: continue
                var shape := PhysicsShapeQueryParameters3D.new()
                shape.shape=capsule
                shape.collision_mask=1
                shape.margin=.001
                shape.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*.845)
                if not space.intersect_shape(shape).is_empty(): continue
                var access := PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.5,item.position+Vector3.UP*.3,1)
                if space.intersect_ray(access).is_empty(): approaches.append(feet)
            counts[item.id]=approaches.size()
            if approaches.size()<2:
                failures+=1
                printerr("FAIL: fewer than two physical supply approaches: ",count_value," ",item.id," ",item.position," ",approaches)
        print("LAYOUT_APPROACHES ",count_value," ",JSON.stringify(counts))
        preview.queue_free()
        await process_frame
    print("Deck layout: ",failures," failures")
    quit(1 if failures else 0)
