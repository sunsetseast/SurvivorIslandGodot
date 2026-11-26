class_name MarooningSupplyVisual
extends Node3D
## Reusable low-cost silhouettes; shared materials, no texture allocations.
static var cloth := MarooningBay.material(Color("bba079"))
static var metal := MarooningBay.material(Color("586268"))
static var green := MarooningBay.material(Color("657c41"))
static var timber := MarooningBay.material(Color("805437"))
func part(mesh: Mesh, point: Vector3, surface: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.position = point
    node.material_override = surface
    add_child(node)
    return node
func rod(point: Vector3, radius: float, height: float, surface: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    return part(mesh,point,surface)
func block(point: Vector3,size: Vector3,surface: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return part(mesh,point,surface)
func build(type: String) -> void:
    var imported := {"rice":"sack", "basket":"basket", "fruit":"basket", "pot":"pot", "rope":"rope_coil", "tools":"axe", "water":"barrel"}
    if imported.has(type):
        var model: Node3D = load("res://marooning/assets/supplies/" + imported[type] + ".glb").instantiate()
        add_child(model)
        var bounds := AABB()
        var first := true
        for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
            var transform := mesh.transform
            var parent := mesh.get_parent() as Node3D
            while parent != null and parent != self:
                transform = parent.transform * transform
                parent = parent.get_parent() as Node3D
            var local: AABB = transform * mesh.get_aabb()
            bounds = local if first else bounds.merge(local)
            first = false
        var factor := .65 / maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
        model.scale *= factor
        model.position = Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z) * factor
        if type == "fruit":
            for i in 4:
                rod(Vector3((i%2)*.16-.08,.4,(i/2)*.16-.08),.09,.14,green)
        return
    match type:
        "rice":
            var sack := SphereMesh.new()
            sack.radius = .29
            sack.height = .65
            sack.radial_segments = 12
            sack.rings = 6
            part(sack,Vector3(0,.32,0),cloth)
            rod(Vector3(0,.65,0),.10,.12,timber)
        "rope":
            for i in 3:
                var ring := TorusMesh.new()
                ring.inner_radius = .13
                ring.outer_radius = .28
                ring.rings = 12
                ring.ring_segments = 8
                part(ring,Vector3(0,.06 + i * .06,0),cloth)
        "bamboo", "wood":
            for i in 4:
                var log := rod(Vector3((i % 2) * .18 - .09,.12 + (i / 2) * .18,0),.085,1.1,green if type == "bamboo" else timber)
                log.rotation.x = PI / 2
        "pot", "cup", "basket", "fruit":
            var radius := .29 if type != "cup" else .15
            rod(Vector3(0,.04,0),radius,.07,metal if type in ["pot","cup"] else cloth)
            for i in 12:
                var angle := i * TAU / 12
                rod(Vector3(sin(angle) * radius,.22,cos(angle) * radius),.035,.4,metal if type in ["pot","cup"] else cloth)
            if type == "fruit":
                for i in 4:
                    rod(Vector3((i%2)*.16-.08,.35,(i/2)*.16-.08),.09,.14,green)
        "machete", "tools", "fishing":
            block(Vector3(0,.04,0),Vector3(.12,.08,.65),metal)
            block(Vector3(0,.06,.4),Vector3(.13,.12,.25),timber)
            if type == "fishing":
                rod(Vector3(.2,.1,0),.2,.15,cloth)
        "tarp", "blanket":
            var roll := rod(Vector3(0,.19,0),.19,.7,green if type == "tarp" else cloth)
            roll.rotation.z = PI / 2
            block(Vector3(0,.2,0),Vector3(.06,.4,.4),timber)
        "coconut":
            for i in 3:
                var fruit := SphereMesh.new()
                fruit.radius = .14
                fruit.height = .28
                fruit.radial_segments = 10
                fruit.rings = 6
                part(fruit,Vector3((i-1)*.2,.14,0),timber)
        _:
            block(Vector3(0,.26,0),Vector3(.45,.52,.35),green)
            block(Vector3(0,.56,0),Vector3(.16,.12,.15),metal)
