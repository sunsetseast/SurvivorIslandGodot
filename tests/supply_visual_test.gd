extends SceneTree
var failures := 0
func _initialize() -> void:
    var summary := {}
    for type: String in MarooningSupplyCatalog.definitions():
        var first := MarooningSupplyVisual.new()
        var second := MarooningSupplyVisual.new()
        first.build(type)
        second.build(type)
        var a: MeshInstance3D = first.get_child(0)
        var b: MeshInstance3D = second.get_child(0)
        if a.mesh != b.mesh or a.mesh.get_faces().is_empty() or a.mesh.get_aabb().position.y < -.03:
            failures += 1
            printerr("FAIL: shared mesh / ground pivot ",type)
        if type=="machete" and (a.mesh.get_aabb().end.z<.4 or a.mesh.get_aabb().size.x<.12):
            failures += 1
            printerr("FAIL: merged blade surface missing")
        if type in ["cup","pot","basket","fruit"] and a.mesh.get_aabb().size.y < .12:
            failures += 1
            printerr("FAIL: vessel silhouette collapsed")
        summary[type] = {"triangles":a.mesh.get_faces().size()/3,"surfaces":a.mesh.get_surface_count(),"dimensions":a.mesh.get_aabb().size}
        first.free()
        second.free()
    print("PROP_AUDIT ",JSON.stringify(summary))
    print("Supply visual: ",failures," failures")
    quit(1 if failures else 0)
