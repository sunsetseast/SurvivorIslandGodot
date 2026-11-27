class_name MarooningShipAccess
extends RefCounted
## Local ship edits: the visible triangles and collision use the identical openings.
static var cache: Dictionary={}

static func windows(layout: MarooningLayout, count_value: int) -> Array[AABB]:
    var result: Array[AABB]=[]
    for index in count_value:
        var gate: Vector3=layout.deck_accesses[index]
        var left := gate.x<0
        result.append(AABB(Vector3(-6.45 if left else 3.1,.45,gate.z-1.2),Vector3(3.35,4.75,2.4)))
    for x: float in [-3,3]: result.append(AABB(Vector3(x-.65,1.8,-8.4),Vector3(1.3,4.9,3.8)))
    return result

static func interpolate(a: Dictionary,b: Dictionary,weight: float) -> Dictionary:
    return {"p":(a.p as Vector3).lerp(b.p,weight),"n":(a.n as Vector3).lerp(b.n,weight).normalized(),"uv":(a.uv as Vector2).lerp(b.uv,weight),"c":(a.c as Color).lerp(b.c,weight)}

static func subtract(polygon: Array, bounds: AABB) -> Array:
    var inside: Array=polygon
    var output: Array=[]
    for plane in 6:
        if inside.is_empty(): break
        var axis: int=plane/2
        var lower := plane%2==0
        var limit: float=bounds.position[axis] if lower else bounds.end[axis]
        var keep: Array=[]
        var outside: Array=[]
        for index in inside.size():
            var a: Dictionary=inside[index]
            var b: Dictionary=inside[(index+1)%inside.size()]
            var ap: Vector3=a.p
            var bp: Vector3=b.p
            var ai := ap[axis]>=limit if lower else ap[axis]<=limit
            var bi := bp[axis]>=limit if lower else bp[axis]<=limit
            if ai: keep.append(a)
            else: outside.append(a)
            if ai!=bi:
                var v := interpolate(a,b,(limit-ap[axis])/(bp[axis]-ap[axis]))
                keep.append(v)
                outside.append(v)
        if outside.size()>=3: output.append(outside)
        inside=keep
    return output

static func open_mesh(source: Mesh, transform: Transform3D, layout: MarooningLayout, count_value: int) -> ArrayMesh:
    var key := str(source.get_instance_id())+":"+str(transform)+":"+str(count_value)
    if cache.has(key): return cache[key]
    var result := ArrayMesh.new()
    var boxes := windows(layout,count_value)
    var inverse := transform.affine_inverse()
    for surface in source.get_surface_count():
        var arrays := source.surface_get_arrays(surface)
        var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
        var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
        var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
        var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
        if indices.is_empty():
            for index in vertices.size(): indices.append(index)
        var tool := SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        var triangles := 0
        for index in range(0,indices.size(),3):
            var polygon: Array=[]
            for offset in 3:
                var i := indices[index+offset]
                polygon.append({"p":transform*vertices[i],"n":normals[i] if not normals.is_empty() else Vector3.UP,"uv":uv[i] if not uv.is_empty() else Vector2.ZERO,"c":colors[i] if not colors.is_empty() else Color.WHITE})
            var pieces: Array=[polygon]
            for box: AABB in boxes:
                var clipped: Array=[]
                for part: Array in pieces: clipped.append_array(subtract(part,box))
                pieces=clipped
            for part: Array in pieces:
                for i in range(1,part.size()-1):
                    for v: Dictionary in [part[0],part[i],part[i+1]]:
                        tool.set_normal(v.n)
                        tool.set_uv(v.uv)
                        tool.set_color(v.c)
                        tool.add_vertex(inverse*(v.p as Vector3))
                    triangles+=1
        if triangles>0:
            tool.index()
            tool.set_material(source.surface_get_material(surface))
            tool.commit(result)
    cache[key]=result
    return result
