extends "res://tools/marooning/review_refinement.gd"
func run() -> void:
    assert(not output.is_empty(),"Set MAROONING_EVIDENCE_DIR outside the export stage")
    DirAccess.make_dir_recursive_absolute(output)
    root.size = Vector2i(956,440)
    root.content_scale_size = Vector2i(1280,720)
    var catalog := SurvivorContestantCatalog.new()
    var success := false
    var failure := false
    for seed_value in range(1,10):
        var setup := SurvivorNewSeasonSetup.new()
        setup.selected_id=18
        var division := SurvivorSeasonConfiguration.new()
        division.seed_value=seed_value
        division.assign(catalog)
        preview=MarooningPreview.new()
        preview.catalog=catalog
        preview.configuration=division.configuration(catalog,setup)
        root.add_child(preview)
        await process_frame
        await tap(preview.skip)
        await frames(60)
        var sim := preview.scramble.simulation
        var victim := 0
        var distance := INF
        for id: int in preview.cast:
            if id==18: continue
            var current := preview.player.position.distance_to(preview.cast[id].position)
            if current<distance:
                victim=id
                distance=current
        # Initial moving-carrier fixture, not an action award. All other bodies/AI remain active.
        sim.items["rice-00"].actor=victim
        sim.items["rice-00"].state=MarooningScramble.State.CARRIED
        await frames(2)
        await walk(preview.cast[victim].position,1.0,240)
        await look_at_point(preview.scramble.visuals["rice-00"].target_point())
        await tap(preview.scramble.start_button)
        await frames(3)
        if preview.scramble.contextual!="steal":
            await look_at_point(preview.scramble.visuals["rice-00"].target_point())
        if preview.scramble.contextual=="steal":
            await capture("seed-%d-target"%seed_value)
            await tap(preview.scramble.action_button)
            await frames(90)
            var stats: Dictionary=sim.contributions[18]
            success = success or int(stats.get("steal_success",0))>0
            failure = failure or int(stats.get("steal_failed",0))>0
            await capture("seed-%d-feedback"%seed_value)
            print("THEFT_GUI ",seed_value," victim ",victim," stats ",stats)
        else:
            print("THEFT_GUI_NO_TARGET ",seed_value," action ",preview.scramble.contextual," target ",preview.scramble.nearest)
            await capture("seed-%d-target-issue"%seed_value)
        preview.queue_free()
        await process_frame
        if success and failure: break
    check(success and failure,"Actual primary-GUI theft success and failure observed")
    print("Theft GUI: ",failures," failures")
    quit(1 if failures else 0)
