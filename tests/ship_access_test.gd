extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        printerr('FAIL: ',message)
func _initialize() -> void: call_deferred('run')
func walk(body: CampPhysicalMotor,goal_x: float,direction: float) -> void:
    for frame in 300:
        await physics_frame
        body.walk_direction(Vector3(direction,0,0),false,1.0/60)
        if (body.position.x-goal_x)*direction>=0: return
func run() -> void:
    var layout := MarooningLayout.new()
    for count_value in [2,3]:
        var bay := MarooningBay.new()
        root.add_child(bay)
        bay.build(layout,count_value)
        for frame in 3: await physics_frame
        for index in count_value:
            var gate: Vector3=layout.deck_accesses[index]
            var side := signf(gate.x)
            var body := CampPhysicalMotor.new()
            body.water=CampWaterSurface.new(0,layout.bed)
            body.position=gate+Vector3.UP*.03
            root.add_child(body)
            for frame in 4: await physics_frame
            await walk(body,side*6.7,side)
            print('SIDE_ACCESS_OUT ',count_value,'/',index,' ',body.position)
            check(absf(body.position.x)>=6.6 and body.position.y>.35 and body.position.y<1.1,'Visible side ramp is continuously walkable without hull clipping')
            await walk(body,side*3.1,-side)
            print('SIDE_ACCESS_RETURN ',count_value,'/',index,' ',body.position)
            check(absf(body.position.x)<=3.2 and body.position.y>1.8,'Moored timber access supports a physical return to deck')
            body.queue_free()
            await physics_frame
        var bow := CampPhysicalMotor.new()
        bow.water=CampWaterSurface.new(0,layout.bed)
        bow.position=Vector3(0,layout.deck_y+.03,7.5)
        root.add_child(bow)
        for frame in 180:
            await physics_frame
            bow.walk_direction(Vector3(0,0,1),false,1.0/60)
        check(bow.position.z<9.2,'Visible bow wall is solid, rather than an invisible gangplank escape')
        bow.queue_free()
        bay.queue_free()
        await physics_frame
    print('Ship side access: ',failures,' failures')
    quit(1 if failures else 0)
