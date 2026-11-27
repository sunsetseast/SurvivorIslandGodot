class_name MarooningRaft
extends AnimatableBody3D
## Replaceable visual assembly. Only the simple box participates in collision.
var visual := Node3D.new()
var paddles: Dictionary = {}
var cargo := Node3D.new()
var draft := 0.0
static var geometry: Dictionary = {}
static var bamboo := MarooningBay.material(Color("92835a"))
static var wood := MarooningBay.timber()
static var rope := MarooningBay.material(Color("d0bb89"))
func part(mesh: Mesh, point: Vector3, material: Material, parent: Node3D = visual) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = material
    node.position = point
    parent.add_child(node)
    return node
func block(point: Vector3, size: Vector3, material: Material, parent: Node3D = visual) -> MeshInstance3D:
    var key := "box:" + str(size)
    if not geometry.has(key):
        var mesh := BoxMesh.new()
        mesh.size = size
        geometry[key] = mesh
    return part(geometry[key],point,material,parent)
func pole(point: Vector3, radius: float, length: float, material: Material, parent: Node3D = visual) -> MeshInstance3D:
    var key := "pole:%s:%s" % [radius,length]
    if not geometry.has(key):
        var mesh := CylinderMesh.new()
        mesh.top_radius = radius * .92
        mesh.bottom_radius = radius
        mesh.height = length
        mesh.radial_segments = 8
        geometry[key] = mesh
    return part(geometry[key],point,material,parent)
func build(members: Array, color: Color) -> void:
    sync_to_physics = false
    collision_layer = 1
    collision_mask = 0
    add_child(visual)
    add_child(cargo)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(3.9,.3,8)
    shape.shape = box
    shape.position.y = -.08
    add_child(shape)
    for i in 13:
        var log := pole(Vector3((i-6)*.30,-.05,0),.17,8,bamboo)
        log.rotation.x = PI/2
        for node_index in 7:
            var collar := pole(Vector3((i-6)*.30,-.05,-3.7+node_index*1.18+float(i%3)*.12),.176,.045,rope)
            collar.rotation.x=PI/2
    for z: float in [-3.4,-1.4,1.4,3.4]:
        block(Vector3(0,.12,z),Vector3(4,.16,.18),wood)
        for x: float in [-1.7,1.7]:
            block(Vector3(x,.15,z),Vector3(.11,.22,.3),rope)
    for i in members.size():
        var position_local := MarooningRace.seat(i)
        block(Vector3(position_local.x,.486,position_local.z-.22),Vector3(.8,.14,.65),wood)
        for dx: float in [-.3,.3]: block(Vector3(position_local.x+dx,.282,position_local.z-.22),Vector3(.09,.27,.48),wood)
        var paddle := Node3D.new()
        paddle.position = position_local + Vector3(-.28 if i%2 == 0 else .28,.65,0)
        visual.add_child(paddle)
        pole(Vector3(0,-.3,0),.035,2.2,wood,paddle)
        block(Vector3(0,-1.45,0),Vector3(.23,.55,.06),wood,paddle)
        paddles[int(members[i])] = paddle
    var tribal := MarooningBay.material(color.darkened(.35))
    block(Vector3(0,.35,-3.5),Vector3(1,.5,.08),tribal)
    for x: float in [-2.0,2.0]:
        for z: float in [-2.0,2.0]:
            block(Vector3(x,.20,z),Vector3(.12,.3,.5),tribal)
    bake_static()
func bake_static() -> void:
    var groups := {}
    for node in visual.get_children():
        if not node is MeshInstance3D: continue
        var key: int=node.material_override.get_instance_id()
        if not groups.has(key):
            var builder := SurfaceTool.new()
            builder.begin(Mesh.PRIMITIVE_TRIANGLES)
            builder.set_material(node.material_override)
            groups[key]=builder
        for surface in node.mesh.get_surface_count(): groups[key].append_from(node.mesh,surface,node.transform)
        node.free()
    for builder: SurfaceTool in groups.values():
        builder.index()
        var batch := MeshInstance3D.new()
        batch.mesh=builder.commit()
        visual.add_child(batch)
func present(raft: Dictionary, actors: Dictionary, time: float, delta: float) -> void:
    draft = move_toward(draft,float(raft.draft),delta*.15)
    position = raft.position - Vector3.UP*draft
    rotation.y = raft.heading
    visual.rotation.z = sin(time*1.5)*.012
    for id: int in paddles:
        paddles[id].visible = actors[id].raft == name
        var phase := clampf((time-float(actors[id].get("stroke_at",-10)))/MarooningRace.STROKE_SECONDS,0,1)
        if float(raft.get("reverse_remaining",0))>0: phase=1.0-phase
        var working: bool=actors[id].paddling and float(actors[id].power)>0
        paddles[id].rotation.x=lerpf(-.65,.65,phase) if working else PI/2
        paddles[id].rotation.z=(-1.0 if int(actors[id].seat_index)%2==0 else 1.0)*.55 if working else 0.0
        paddles[id].position.y=MarooningRace.seat(int(actors[id].seat_index)).y+(.65 if working else .18)
