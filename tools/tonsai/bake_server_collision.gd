extends SceneTree
## Runs at build time on the existing client stage. Only shapes enter the server.

func _initialize() -> void:
    call_deferred("_bake")

func _bake() -> void:
    var site := TonsaiSiteData.new()
    if not site.load_inputs():
        quit(1)
        return
    var terrain := TonsaiTerrain.new()
    var kit := TonsaiEnvironmentKit.new()
    root.add_child(terrain)
    root.add_child(kit)
    terrain.build(site)
    if not kit.build(site, terrain):
        quit(1)
        return
    var collision := Node3D.new()
    collision.name = "TonsaiCollision"
    root.add_child(collision)
    for source: Node3D in [terrain, kit]:
        for child: Node in source.get_children():
            if child is StaticBody3D:
                child.reparent(collision, true)
                child.owner = collision
                for shape: Node in child.get_children():
                    shape.owner = collision
    var scene := PackedScene.new()
    if collision.get_child_count() < 20 or scene.pack(collision) != OK \
            or ResourceSaver.save(scene, TonsaiSiteData.DIR + "server_collision.scn", ResourceSaver.FLAG_COMPRESS) != OK:
        quit(1)
        return
    print("Baked Tonsai collision bodies: ", collision.get_child_count())
    quit()
