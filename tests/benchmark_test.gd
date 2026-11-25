extends SceneTree
var failures := 0
func _initialize() -> void:
    call_deferred("_test")
func _test() -> void:
    var benchmark: Variant = load("res://diagnostics/mobile_benchmark.gd").new()
    root.add_child(benchmark)
    for environment in [false, true]:
        for quality in [false, true]:
            for rigs in [1, 6, 12, 18]:
                benchmark.tonsai = environment
                benchmark.economy = quality
                benchmark.count = rigs
                benchmark._rebuild()
                if benchmark.actors.size() != rigs or benchmark.sim._simulation.roster.size() != 18:
                    failures += 1
                await process_frame
    benchmark.free()
    await process_frame
    print("Benchmark 16 scenarios: ", failures, " failures")
    quit(int(failures > 0))
