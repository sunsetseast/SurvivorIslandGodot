class_name MarooningBay
extends Node3D
var layout: MarooningLayout
var markers: Dictionary = {}
var wood := timber()
var bamboo := material(Color("ac9360"))
var sand := material(Color("dbcd9b"))

static func timber() -> ShaderMaterial:
    var result := ShaderMaterial.new()
    result.shader = preload("res://marooning/wood.gdshader")
    return result

static func material(color: Color) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.roughness = .88
    return result

func mark(id: String, point: Vector3) -> Marker3D:
    var marker := Marker3D.new()
    marker.name = id
    marker.position = point
    add_child(marker)
    markers[id] = marker
    return marker

func shape(id: String, mesh: Mesh, point: Vector3, surface: Material, solid := false) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = id
    node.mesh = mesh
    node.material_override = surface
    node.position = point
    add_child(node)
    if solid:
        var body := StaticBody3D.new()
        node.add_child(body)
        var collider := CollisionShape3D.new()
        if mesh is BoxMesh:
            var box_shape := BoxShape3D.new()
            box_shape.size = mesh.size
            collider.shape = box_shape
        else:
            collider.shape = mesh.create_convex_shape()
        body.add_child(collider)
    return node

func box(id: String, point: Vector3, size: Vector3, surface: Material, solid := true) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return shape(id, mesh, point, surface, solid)

func pole(id: String, point: Vector3, radius: float, height: float, surface: Material, solid := false) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius * .88
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    return shape(id, mesh, point, surface, solid)

func build(data: MarooningLayout, tribe_count: int) -> void:
    layout = data
    var environment := WorldEnvironment.new()
    var atmosphere := Environment.new()
    var sky := Sky.new()
    var sky_material := PanoramaSkyMaterial.new()
    sky_material.panorama = load("res://world/assets/kloofendal-clear.jpg")
    sky.sky_material = sky_material
    atmosphere.background_mode = Environment.BG_SKY
    atmosphere.sky = sky
    atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    atmosphere.ambient_light_color = Color("c0d7e1")
    atmosphere.ambient_light_energy = .43
    environment.environment = atmosphere
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -30, 0)
    sun.light_color = Color("fff1d7")
    sun.light_energy = .99
    add_child(sun)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for z in range(-210, 210, 5):
        for x in range(-210, 210, 5):
            for offset: Vector2 in [Vector2(0, 0), Vector2(5, 0), Vector2(0, 5), Vector2(5, 0), Vector2(5, 5), Vector2(0, 5)]:
                var point := Vector3(x + offset.x, 0, z + offset.y)
                point.y = layout.bed(point.x, point.z)
                surface.set_uv(Vector2(point.x, point.z) * .2)
                surface.add_vertex(point)
    surface.generate_normals()
    var shore_surface := ShaderMaterial.new()
    shore_surface.shader = preload("res://marooning/sand.gdshader")
    shore_surface.set_shader_parameter("sand_detail", load("res://tonsai/generated/sand_02-diff.jpg"))
    shore_surface.set_shader_parameter("leaf_detail",load("res://tonsai/generated/brown_mud_leaves_01-diff.jpg"))
    var bed_mesh := surface.commit()
    shape("BaySeabed", bed_mesh, Vector3.ZERO, shore_surface)
    var bed_body := StaticBody3D.new()
    var bed_shape := CollisionShape3D.new()
    bed_shape.shape = bed_mesh.create_trimesh_shape()
    bed_shape.shape.backface_collision=true
    bed_body.add_child(bed_shape)
    add_child(bed_body)
    var sea := PlaneMesh.new()
    sea.size = Vector2(1600, 1600)
    var water := ShaderMaterial.new()
    water.shader = load("res://world/water.gdshader")
    water.set_shader_parameter("ripples", load("res://world/assets/water-ripple.png"))
    shape("TropicalSea", sea, Vector3.ZERO, water)
    var stone_source: Node3D = load("res://tonsai/generated/limestone.glb").instantiate()
    var stone_parts := stone_source.find_children("*", "MeshInstance3D", true, false)
    var rock_material := ShaderMaterial.new()
    rock_material.shader = load("res://tonsai/shaders/rock.gdshader")
    rock_material.set_shader_parameter("limestone", load("res://tonsai/generated/rock_06_diff_1k.jpg"))
    # One authored LOD per rock: rendering near and far together caused z-fighting.
    for i in 7:
        var point := Vector3(-126+i*43,0,213+(i%3)*17)
        for part: MeshInstance3D in stone_parts:
            if "far" not in String(part.name): continue
            var rock := shape("Limestone%d" % i,part.mesh,point,rock_material)
            rock.scale=Vector3(25+float(i%3)*9,18+float(i%2)*8,23)
            rock.rotation.y=i*1.7
            var bounds := part.mesh.get_aabb()
            # Seat the actual bottom of the selected mesh below the physical terrain.
            rock.position.y=layout.bed(point.x,point.z)-bounds.position.y*rock.scale.y-.5
            rock.visibility_range_end=650
    stone_source.free()
    _shore()
    _ship(tribe_count)
    _access_ramps(tribe_count)
    _loading_lines(tribe_count)
    for i in tribe_count:
        var mount := layout.raft_mounts[i]
        mark("raft-mount-%d" % i, mount)
    mark("departure-access",layout.deck_accesses[0])
    mark("reward-dock", layout.reward)
    box("FloatingRewardDock", layout.reward, Vector3(5, .35, 5), wood)
    for x: float in [-2.2, 2.2]:
        for z: float in [-2.2, 2.2]:
            pole("DockPost", layout.reward + Vector3(x, .6, z), .11, 1.4, wood)
    mark("reward-" + layout.reward_id, layout.reward + Vector3.UP)
    box("IllustrativeFishingPackage", layout.reward + Vector3.UP * .7, Vector3(1.2, 1, .9), bamboo)
    # Matching visible access ramp lets a swimmer wade onto the stationary dock.
    var ramp := box("DockAccessRamp", layout.reward + Vector3(0, -.6, 4), Vector3(2, .15, 4), wood)
    ramp.rotation.x = .45
    mark("player-landing", layout.landing)
    mark("future-camp-transition", layout.landing + Vector3(0, 1, 16))
    for i in layout.rival_exits.size():
        mark("rival-exit-%d" % i, layout.rival_exits[i])
    pole("LandingFlagPost", layout.landing + Vector3(3, 2, 0), .08, 4, wood)
    box("LandingFlag", layout.landing + Vector3(3.7, 3.5, 0), Vector3(1.4, .7, .05), material(Color("e6c777")), false)

func _shore() -> void:
    # Reuse the actual Tonsai library. All grading is local to this preview.
    var library := {}
    for file: String in ["palms","reconstruction-low","fern_02","coastal-tree"]:
        var source: Node3D=load("res://tonsai/generated/"+file+".glb").instantiate()
        for part: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
            var mesh := part.mesh.duplicate() as ArrayMesh
            for index in mesh.get_surface_count():
                var original := mesh.surface_get_material(index)
                if not original is StandardMaterial3D: continue
                var foliage := original.duplicate() as StandardMaterial3D
                foliage.vertex_color_use_as_albedo=true
                if "leaves" in String(part.name) or "crown" in String(part.name) or file=="fern_02":
                    foliage.albedo_color*=Color("849856")
                    foliage.cull_mode=BaseMaterial3D.CULL_DISABLED
                    foliage.metallic_specular=.08
                    foliage.roughness=.97
                elif "wood" in String(part.name) or "trunk" in String(part.name):
                    foliage.albedo_color*=Color("76694f")
                    foliage.roughness=.98
                    foliage.metallic_specular=.05
                mesh.surface_set_material(index,foliage)
            library[String(part.name)]=mesh
        source.free()
    for variant in 3:
        var close: Array[Transform3D]=[]
        var distant: Array[Transform3D]=[]
        var forest: Array[Transform3D]=[]
        var understory: Array[Transform3D]=[]
        for i in 18:
            var x := -91.0+i*10.5+float(variant)*2.3
            var z := 181.0+float(variant)*5.5+sin(i*2.3+variant)*3.8
            var point := Vector3(x,layout.bed(x,z)-.05,z)
            var basis := Basis(Vector3.UP,i*2.1+variant).scaled(Vector3.ONE*(.72+float((i+variant)%4)*.1))
            close.append(Transform3D(basis,point))
            var far_point := point+Vector3(0,0,28)
            distant.append(Transform3D(basis,far_point))
            forest.append(Transform3D(basis.scaled(Vector3.ONE*1.4),point+Vector3(4,0,21)))
        for i in 32:
            var x := -100.0+float(i%16)*13.1+variant*1.5
            var z := 179.0+float(i/16)*13+variant*5
            understory.append(Transform3D(Basis(Vector3.UP,i*2.3).scaled(Vector3.ONE*(.8+float(i%3)*.23)),Vector3(x,layout.bed(x,z),z)))
        _foliage_batch(library,["palm-%d-near-wood"%variant,"palm-%d-near-leaves"%variant],close,0,72)
        _foliage_batch(library,["palm-%d-far-wood"%variant,"palm-%d-far-leaves"%variant],close,72,420)
        _foliage_batch(library,["palm-%d-far-wood"%variant,"palm-%d-far-leaves"%variant],distant,0,420)
        _foliage_batch(library,["forest-%d-wood-far"%variant,"forest-%d-crown-far"%variant],forest,0,400)
        _foliage_batch(library,["understory-%d-leaves-far"%variant],understory,0,85)
        _foliage_batch(library,["fern_02_"+["a","b","c"][variant]],understory,0,55)
func _foliage_batch(library: Dictionary, keys: Array, transforms: Array[Transform3D], start: float, end: float) -> void:
    for key: String in keys:
        if not library.has(key): continue
        var batch := MultiMesh.new()
        batch.transform_format=MultiMesh.TRANSFORM_3D
        batch.mesh=library[key]
        batch.instance_count=transforms.size()
        for i in transforms.size(): batch.set_instance_transform(i,transforms[i])
        var node := MultiMeshInstance3D.new()
        node.multimesh=batch
        node.visibility_range_begin=start
        node.visibility_range_end=end
        node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(node)

func _loading_lines(count_value: int) -> void:
    var line_material := material(Color("8e7951"))
    for index in count_value:
        var station: Vector3=layout.collection_centres[index]
        var gate: Vector3=layout.deck_accesses[index]
        var side := signf(gate.x)
        var points: Array[Vector3]=[station+Vector3(side*.15,.18,.6),Vector3(side*3.7,1.88,gate.z-.78),Vector3(side*6.75,.6,gate.z-.78)]
        for i in range(1,points.size()):
            var start := points[i-1]
            var finish := points[i]
            for offset: float in [-.19,.19]:
                var rail := pole("CargoHaulRail",(start+finish)*.5+Vector3(0,.06,offset),.04,start.distance_to(finish),wood)
                rail.quaternion=Quaternion(Vector3.UP,start.direction_to(finish))
            for step in 8:
                var roller := pole("CargoRoller",start.lerp(finish,float(step)/7),.055,.42,line_material)
                roller.rotation.x=PI/2
        var winch := pole("CargoHandlineReel",station+Vector3(0,.6,.95),.15,.12,line_material)
        winch.rotation.x=PI/2

func _ship(tribe_count: int) -> void:
    var vessel: Node3D = load("res://marooning/assets/galleon.glb").instantiate()
    vessel.name = "MarooningShip"
    vessel.position = layout.ship_origin
    add_child(vessel)
    for node: Node in vessel.find_children("*", "Node3D", true, false):
        if "gunport" in String(node.name) or "furled" in String(node.name):
            (node as Node3D).hide()
    mark("ship", layout.ship_origin)
    mark("deck", Vector3(0, layout.deck_y, 0))
    mark("host", Vector3(1.8, layout.deck_y, -4.5))
    mark("overboard-access", Vector3(4.3, layout.deck_y, 8))
    # Imported transforms are retained: body/fittings contain walls, masts and hull.
    # Concave static shapes preserve openings instead of convexly sealing the ship.
    for part: MeshInstance3D in vessel.find_children("*", "MeshInstance3D", true, false):
        if part.is_visible_in_tree() and (part.name == "body" or part.name == "fittings"):
            part.mesh=MarooningShipAccess.open_mesh(part.mesh,part.global_transform,layout,tribe_count)
            var body := StaticBody3D.new()
            var collision := CollisionShape3D.new()
            collision.shape=part.mesh.create_trimesh_shape()
            body.add_child(collision)
            part.add_child(body)
    # Continuous safety floor beneath all designated cargo circulation areas.
    box("OpenDeck", Vector3(0, layout.deck_y - .13, 1.5), Vector3(8, .26, 16), wood)
    box("HostPlatform", Vector3(0, layout.deck_y + 2.6, -11.5), Vector3(7.6, .4, 4), wood)
    for stair_x: float in [-3.0,3.0]:
        var ramp := box("StairCollisionRamp",Vector3(stair_x,3.43,-5.75),Vector3(1.05,.16,6.0),wood)
        ramp.rotation.x = atan2(3.1,5.1)
        # Visible timber access matches its continuous collision ramp.
        ramp.show()
    for side: float in [-1,1]:
        var intervals: Array[Vector2]=[Vector2(-6.5,6.9)]
        for index in tribe_count:
            var gate: Vector3=layout.deck_accesses[index]
            if signf(gate.x)!=side: continue
            var next: Array[Vector2]=[]
            for section: Vector2 in intervals:
                if gate.z-1.2>section.x: next.append(Vector2(section.x,minf(section.y,gate.z-1.2)))
                if gate.z+1.2<section.y: next.append(Vector2(maxf(section.x,gate.z+1.2),section.y))
            intervals=next
        for section: Vector2 in intervals:
            if section.y-section.x>.05:
                box("DeckRail",Vector3(side*4,layout.deck_y+.6,(section.x+section.y)*.5),Vector3(.12,1.2,section.y-section.x),wood)
    var mast := StaticBody3D.new()
    mast.name = "MainMastCollision"
    mast.position = Vector3(0, layout.deck_y + 5, -3.5)
    var mast_shape := CollisionShape3D.new()
    var cylinder := CylinderShape3D.new()
    cylinder.radius = .42
    cylinder.height = 10
    mast_shape.shape = cylinder
    mast.add_child(mast_shape)
    add_child(mast)
    box("ClosedBowRail",Vector3(0,layout.deck_y+.6,9.5),Vector3(8,1.2,.12),wood)
    for i in 3:
        mark("spawn-group-%d" % i, Vector3(-2.4 + i * 2.4, layout.deck_y, 2))
    # Retain semantic legacy anchors for downstream tools, without solid cargo props.
    for i in 6:
        mark("cargo-" + ["rice-sack","crate","rope","basket","cooking-pot","survival-kit"][i], Vector3(3.0,layout.deck_y,-4+i*1.5))

func _access_ramps(tribe_count: int) -> void:
    var angle := atan2(1.32,2.8)
    var length := Vector2(2.8,1.32).length()
    for index in tribe_count:
        var gate: Vector3=layout.deck_accesses[index]
        var side := signf(gate.x)
        mark("access-%d"%index,gate)
        mark("access-water-%d"%index,Vector3(side*5.8,-1.07,gate.z+3.1))
        var ramp := box("TimberSideAccess%d"%index,Vector3(side*5.45,1.167,gate.z),Vector3(length,.16,2.2),wood)
        ramp.rotation.z=-side*angle
        box("GateThreshold%d"%index,Vector3(side*3.7,layout.deck_y-.07,gate.z),Vector3(.8,.14,2.2),wood)
        for i in 11:
            var x := 4.1+float(i)*.26
            var y := 1.9-(x-4.05)*1.32/2.8
            var tread := box("RampTread",Vector3(side*x,y+.01,gate.z),Vector3(.06,.018,2.1),bamboo,false)
            tread.rotation.z=-side*angle
        for z_offset: float in [-1.16,1.16]:
            for x: float in [4.15,5.45,6.75]:
                var floor_y := 1.9-(x-4.05)*1.32/2.8
                pole("RampRailPost",Vector3(side*x,floor_y+.5,gate.z+z_offset),.055,1.0,wood,true)
            var rail := pole("RampRopeRail",Vector3(side*5.45,1.74,gate.z+z_offset),.025,length,material(Color("9d8864")),false)
            rail.rotation.z=PI/2-side*angle
        var sign_mesh := box("OpenSideGate",Vector3(side*3.9,2.65,gate.z-1.28),Vector3(.5,.4,.08),wood,false)
        sign_mesh.set_meta("access_index",index)

func cut_stair(triangle: PackedVector3Array, bounds: AABB) -> PackedVector3Array:
    # Subtract only the stair corridor from broad imported wall/rail triangles.
    var inside := triangle
    var output := PackedVector3Array()
    for plane in 6:
        if inside.is_empty():
            break
        var axis := plane / 2
        var lower := plane % 2 == 0
        var limit: float = bounds.position[axis] if lower else bounds.end[axis]
        var keep := PackedVector3Array()
        var outside := PackedVector3Array()
        for i in inside.size():
            var a := inside[i]
            var b := inside[(i+1)%inside.size()]
            var ai: bool = a[axis] >= limit if lower else a[axis] <= limit
            var bi: bool = b[axis] >= limit if lower else b[axis] <= limit
            if ai:
                keep.append(a)
            else:
                outside.append(a)
            if ai != bi:
                var point := a.lerp(b,(limit-a[axis])/(b[axis]-a[axis]))
                keep.append(point)
                outside.append(point)
        for i in range(1,outside.size()-1):
            output.append_array(PackedVector3Array([outside[0],outside[i],outside[i+1]]))
        inside = keep
    return output
