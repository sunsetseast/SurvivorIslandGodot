class_name MarooningSupplyVisual
extends Node3D
## Original metre-scale meshes. Cached per type, merged by material to bound draw calls.
static var cache: Dictionary = {}
static var cloth := surface(Color("ac9470"),1.0)
static var metal := steel()
static func steel() -> StandardMaterial3D:
    var result := MarooningBay.material(Color("8a9394"))
    result.cull_mode = BaseMaterial3D.CULL_DISABLED
    result.metallic = .35
    result.roughness = .46
    return result
static var green := surface(Color("76815e"),.6)
static var timber := surface(Color("64472f"),.0)
static var light := surface(Color("a48c57"),.8)
static var dark := surface(Color("3f382c"),.1)
static func surface(color: Color, weave: float) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = preload("res://marooning/prop_surface.gdshader")
    material.set_shader_parameter("tint",color)
    material.set_shader_parameter("weave",weave)
    return material
func part(mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.position = point
    node.material_override = material
    add_child(node)
    return node
func rod(point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius*.92
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 12
    mesh.rings = 1
    return part(mesh,point,material)
func block(point: Vector3,size: Vector3,material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return part(mesh,point,material)
func ball(point: Vector3,size: Vector3,material: Material) -> void:
    var mesh := SphereMesh.new()
    mesh.radius = .5
    mesh.height = 1
    mesh.radial_segments = 16
    mesh.rings = 8
    part(mesh,point,material).scale = size
func ring(point: Vector3, radius: float, thickness: float, material: Material) -> MeshInstance3D:
    var mesh := TorusMesh.new()
    mesh.inner_radius = radius-thickness
    mesh.outer_radius = radius+thickness
    mesh.rings = 24
    mesh.ring_segments = 6
    return part(mesh,point,material)
func vessel(radius: float,height: float,material: Material,offset := Vector3.ZERO) -> void:
    rod(offset+Vector3.UP*.025,radius,.05,material)
    # Closed wall with visible inner surface and continuous open lip.
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var points: Array[Vector2] = [Vector2(radius*.8,.025),Vector2(radius,height),Vector2(radius-.025,height),Vector2(radius*.8-.025,.05)]
    for i in 24:
        for j in 4:
            var corners: Array[Vector3] = []
            for pair: Vector2i in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,(j+1)%4),Vector2i(i,(j+1)%4)]:
                var p := points[pair.y]
                var a := pair.x*TAU/24.0
                corners.append(Vector3(sin(a)*p.x,p.y,cos(a)*p.x))
            for index in [0,1,2,0,2,3]: tool.add_vertex(corners[index])
    tool.generate_normals()
    tool.index()
    part(tool.commit(),offset,material)
    ring(offset+Vector3.UP*height,radius,.018,material)
func blade() -> void:
    # Swept taper, broad belly and rounded clipped point; a game prop only.
    var outline := PackedVector2Array([Vector2(-.035,-.23),Vector2(.035,-.23),Vector2(.07,.15),Vector2(.10,.28),Vector2(.08,.38),Vector2(.025,.45),Vector2(-.035,.32)])
    var indices := Geometry2D.triangulate_polygon(outline)
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for y: float in [.022,.035]:
        for i in range(0,indices.size(),3):
            for k in ([2,1,0] if y==.035 else [0,1,2]):
                var p := outline[indices[i+k]]
                tool.add_vertex(Vector3(p.x,y,p.y))
    for i in outline.size():
        var a := outline[i]
        var b := outline[(i+1)%outline.size()]
        for v: Vector3 in [Vector3(a.x,.022,a.y),Vector3(b.x,.022,b.y),Vector3(b.x,.035,b.y),Vector3(a.x,.022,a.y),Vector3(b.x,.035,b.y),Vector3(a.x,.035,a.y)]: tool.add_vertex(v)
    tool.generate_normals()
    tool.index()
    part(tool.commit(),Vector3.ZERO,metal)
    var handle := rod(Vector3(0,.035,-.34),.032,.22,timber)
    handle.rotation.x = PI/2
    for z: float in [-.40,-.29]: rod(Vector3(0,.064,z),.008,.008,metal)
func build(type: String) -> void:
    if cache.has(type):
        part(cache[type],Vector3.ZERO,null)
        return
    match type:
        "rice":
            ball(Vector3(0,.23,0),Vector3(.40,.47,.55),cloth)
            ball(Vector3(0,.46,0),Vector3(.15,.15,.17),cloth)
            ring(Vector3(0,.45,0),.073,.012,dark)
        "machete": blade()
        "pot":
            vessel(.25,.24,metal)
            for x: float in [-.29,.29]: ring(Vector3(x,.20,0),.065,.014,metal).rotation.z = PI/2
        "cup":
            for i in 3:
                var p := Vector3(0,i*.05,0)
                vessel(.068,.13,metal,p)
                ring(p+Vector3(.085,.08,0),.034,.008,metal).rotation.z = PI/2
        "basket", "fruit":
            vessel(.26,.30,cloth)
            for i in 14: ring(Vector3(0,.04+i*.019,0),.215+i*.0032,.009,light)
            for i in 16:
                var angle := i*TAU/16
                rod(Vector3(sin(angle)*.239,.16,cos(angle)*.239),.009,.29,timber)
            for x: float in [-.27,.27]: ring(Vector3(x,.3,0),.065,.012,cloth).rotation.z = PI/2
            if type == "fruit":
                for i in 7: ball(Vector3(sin(i*2.4)*.14,.32+(i%2)*.05,cos(i*2.4)*.14),Vector3(.14,.14,.14),green if i%2 else light)
        "water":
            ball(Vector3(0,.25,0),Vector3(.35,.48,.30),light)
            rod(Vector3(0,.5,0),.055,.08,timber)
            ring(Vector3(.14,.43,0),.08,.018,cloth).rotation.z = PI/2
        "rope":
            for i in 6: ring(Vector3(0,.025+i*.018,0),.16+(i%2)*.015,.015,cloth)
            var end := rod(Vector3(.20,.04,.1),.015,.28,cloth)
            end.rotation.z = PI/2
        "bamboo", "wood":
            for i in 5:
                var p := Vector3((i%3-1)*.11,.06+(i/3)*.10,0)
                var log := rod(p,.046 if type=="bamboo" else .055,1.3 if type=="bamboo" else .65,green if type=="bamboo" else timber)
                log.rotation.x = PI/2
                log.rotation.y = (i-2)*.045
                if type=="bamboo":
                    for z: float in [-.5,-.18,.18,.5]: rod(p+Vector3(0,0,z),.051,.014,light).rotation.x = PI/2
                    for z: float in [-.65,.65]:
                        rod(p+Vector3(0,0,z),.043,.008,light).rotation.x=PI/2
                        rod(p+Vector3(0,0,z+signf(z)*.005),.027,.009,dark).rotation.x=PI/2
                else:
                    var split := block(p+Vector3(.025,.02,0),Vector3(.04,.06,.62),light)
                    split.rotation.y = (i-2)*.045
            for z: float in [-.22,.22]:
                var tie := ring(Vector3(0,.115,z),.17,.018,cloth)
                tie.scale.z = .62
                tie.rotation.x = PI/2
        "coconut":
            rod(Vector3(0,.29,-.1),.012,.5,cloth).rotation.z=PI/2
            ring(Vector3(0,.36,-.1),.07,.012,cloth).rotation.x=PI/2
            for i in 3:
                var p := Vector3((i-1)*.22,.13,(i%2)*.12)
                ball(p,Vector3(.23,.25,.22),timber)
                for j in 3: rod(p+Vector3((j-1)*.025,.12,0),.0065,.009,dark)
        "tarp", "blanket":
            var roll := rod(Vector3(0,.14,0),.13,.65,green if type=="tarp" else cloth)
            roll.rotation.z = PI/2
            for x: float in [-.22,.22]: ring(Vector3(x,.14,0),.135,.013,dark).rotation.z = PI/2
            for x: float in [-.33,.33]: ring(Vector3(x,.14,0),.09,.012,light).rotation.z = PI/2
        "fishing":
            for i in 9:
                var line := rod(Vector3((i-4)*.035,.025,0),.007,.42,cloth)
                line.rotation.x = PI/2
                var cross := rod(Vector3(0,.027,(i-4)*.045),.007,.33,cloth)
                cross.rotation.z = PI/2
            for i in 3: ring(Vector3(.25,.035+i*.018,0),.075,.01,cloth)
            rod(Vector3(-.24,.05,0),.035,.09,timber)
        "tools":
            rod(Vector3(0,.08,-.17),.012,.25,cloth).rotation.z=PI/2
            ring(Vector3(0,.12,-.17),.06,.01,cloth).rotation.x=PI/2
            var handle := rod(Vector3(-.09,.045,0),.025,.43,timber)
            handle.rotation.x = PI/2
            ball(Vector3(-.09,.045,.25),Vector3(.12,.045,.20),metal)
            var mallet := rod(Vector3(.12,.045,0),.025,.4,timber)
            mallet.rotation.x = PI/2
            rod(Vector3(.12,.065,.17),.06,.18,timber).rotation.z = PI/2
    # Merge transformed triangles into one cached mesh with one surface per material.
    var groups := {}
    for node: MeshInstance3D in get_children():
        var material: Material = node.material_override
        if not groups.has(material): groups[material] = SurfaceTool.new(); groups[material].begin(Mesh.PRIMITIVE_TRIANGLES)
        groups[material].append_from(node.mesh,0,node.transform)
    var merged := ArrayMesh.new()
    for material: Material in groups:
        groups[material].set_material(material)
        groups[material].commit(merged)
    for child: Node in get_children(): child.free()
    cache[type] = merged
    part(merged,Vector3.ZERO,null)

func target_point() -> Vector3:
    var mesh: MeshInstance3D = get_child(0)
    return mesh.to_global(mesh.mesh.get_aabb().get_center())
static func carry_grip(type: String) -> Dictionary:
    var grips := {
        "rice":[Vector3(0,.48,0),Vector3.ZERO],
        "machete":[Vector3(0,.035,-.34),Vector3(PI/2,0,0)],
        "pot":[Vector3(.29,.26,0),Vector3.ZERO],
        "water":[Vector3(.14,.51,0),Vector3.ZERO],
        "fishing":[Vector3(.25,.06,.075),Vector3(0,PI/2,0)],
        "tarp":[Vector3(0,.14,-.13),Vector3(0,0,PI/2)],
        "rope":[Vector3(.1,.06,-.145),Vector3(PI/2,0,0)],
        "bamboo":[Vector3(.16,.115,0),Vector3(PI/2,0,0)],
        "coconut":[Vector3(0,.43,-.1),Vector3(0,-PI/2,0)],
        "fruit":[Vector3(.27,.36,0),Vector3.ZERO],
        "wood":[Vector3(.16,.115,0),Vector3(PI/2,0,0)],
        "blanket":[Vector3(0,.14,-.13),Vector3(0,0,PI/2)],
        "basket":[Vector3(.27,.36,0),Vector3.ZERO],
        "cup":[Vector3(.085,.21,0),Vector3.ZERO],
        "tools":[Vector3(0,.18,-.17),Vector3(0,-PI/2,0)]}
    return {"point":grips[type][0],"rotation":grips[type][1]}
