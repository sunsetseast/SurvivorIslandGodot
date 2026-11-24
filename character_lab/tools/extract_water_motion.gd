extends SceneTree
## Run in a Godot project that has imported the intermediate motion and public model GLBs.
## Args after -- are the imported motion, imported public model, and output .res paths.

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var source := (load(args[0]) as PackedScene).instantiate()
    var target := (load(args[1]) as PackedScene).instantiate()
    var source_player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
    var target_player := target.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
    var walk := target_player.get_animation(&"Walk")
    var library := AnimationLibrary.new()
    for clip in [&"Swim", &"Tread"]:
        var animation := source_player.get_animation(clip)
        assert(animation != null)
        for track in range(animation.get_track_count() - 1, -1, -1):
            var path := animation.track_get_path(track)
            if path.get_subname_count() != 1 or walk.find_track(path, Animation.TYPE_ROTATION_3D) < 0:
                animation.remove_track(track)
        assert(animation.get_track_count() >= 40)
        animation.loop_mode = Animation.LOOP_LINEAR
        library.add_animation(clip, animation)
    source.free()
    target.free()
    quit(int(ResourceSaver.save(library, args[2], ResourceSaver.FLAG_COMPRESS) != OK))
