extends SceneTree
## Generate an actual game checkpoint for the API test. No fabricated roster.

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    assert(args.size() == 1)
    var simulation := SeasonSimulation.new("a".repeat(32), "b".repeat(32), 1048573)
    for tick in 100:
        simulation.advance("")
    var local := SaveCodec.encode(simulation.snapshot(), 1, 1735689600)
    var restored := SaveCodec.decode(local)
    assert(restored.status == "valid")
    # This also covers the floating-point representation seen after Web import
    # and restoration, where a round-tripped tick is serialized as 100.0.
    var upload := SaveCodec.encode(restored.state, int(restored.save_revision), int(restored.timestamp))
    var file := FileAccess.open(args[0], FileAccess.WRITE)
    assert(file != null)
    file.store_string(upload)
    file.close()
    print("Integration checkpoint: %d bytes" % upload.to_utf8_buffer().size())
    quit()
