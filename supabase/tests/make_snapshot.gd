extends SceneTree
## Generate an actual game checkpoint for the API test. No fabricated roster.

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    assert(args.size() == 1)
    var simulation := SeasonSimulation.new("a".repeat(32), "b".repeat(32), 1048573)
    for tick in 100:
        simulation.advance("")
    var local := SaveCodec.encode(simulation.snapshot(), 1, 1735689600)
    assert(SaveCodec.decode(local).status == "valid")
    var file := FileAccess.open(args[0], FileAccess.WRITE)
    assert(file != null)
    file.store_string(local)
    file.close()
    print("Integration checkpoint: %d bytes" % local.to_utf8_buffer().size())
    quit()
