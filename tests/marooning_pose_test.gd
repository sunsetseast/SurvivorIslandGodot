extends SceneTree
## Geometry fixture, separate from genuine-input gameplay acceptance.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",label)
func run() -> void:
    root.size=Vector2i(956,440)
    var catalog: SurvivorContestantCatalog=load("res://tests/marooning_test.gd").fixture()
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id=18
    var division := SurvivorSeasonConfiguration.new()
    division.assign(catalog)
    var preview := MarooningPreview.new()
    preview.catalog=catalog
    preview.configuration=division.configuration(catalog,setup)
    root.add_child(preview)
    await process_frame
    preview.finish_intro()
    preview.set_physics_process(false)
    for id: int in preview.cast:
        var state: Dictionary=preview.session.race.actors[id]
        state.place="aboard"
        state.raft=state.tribe
        state.mode="aboard"
        state.stroke_at=0
        preview.session.race.rafts[state.tribe].crew.append(id)
    var max_error := 0.0
    for phase_value: float in [0.0,.25,.5,.75,1.0]:
        preview.session.race.elapsed=phase_value*MarooningRace.STROKE_SECONDS
        for raft: Dictionary in preview.session.race.rafts.values(): preview.session.race.update_mass(raft)
        for id: int in preview.cast:
            var state: Dictionary=preview.session.race.actors[id]
            state.power=100.0 if phase_value<1 else 0.0
            state.position=preview.session.race.to_world(state.tribe,MarooningRace.seat(int(state.seat_index)))
        preview.race.present(1.0/60)
        for frame in 20: await process_frame
        RenderingServer.force_draw(true)
        for id: int in preview.cast:
            var body: CampHumanoidMotor=preview.cast[id]
            var pose: MarooningPose=body.get_meta("marooning_pose")
            check(pose.modification_count>0,"Post-mixer modifier actually ran")
            if phase_value<1:
                check(pose.grip_errors.size()==2,"Both actual hands were measured after the mixer")
                for error in pose.grip_errors.values():
                    max_error=maxf(max_error,float(error))
                    check(float(error)<.08,"Working hands follow actual shaft within8cm")
            check(body.motion_clip==&"Seated","Attached actor cannot stand/run")
            var skeleton: Skeleton3D=body.presentation.skeleton
            var hip := skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).origin.y+.08
            var foot := skeleton.get_bone_global_pose(skeleton.find_bone("foot_l")).origin.y+.08
            check(absf(hip-.556)<.04,"Hips contact real bench top")
            check(absf(foot-.15)<.04,"Feet contact bamboo deck")
    print("POSE_GEOMETRY eighteen temporary rigs · maximum grip error metres=",max_error)
    preview.queue_free()
    await process_frame
    print("Marooning poses: ",failures," failures")
    quit(1 if failures else 0)
