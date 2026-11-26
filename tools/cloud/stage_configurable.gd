extends SceneTree
# Intentional private staging only. Output must remain outside public source/artifacts.
func _initialize() -> void:
    var source := OS.get_environment("SURVIVOR_PRIVATE_CATALOG")
    var output := OS.get_environment("SURVIVOR_PRIVATE_CLOUD_STAGE")
    output = output.simplify_path()
    if OS.get_environment("GITHUB_ACTIONS") == "true" or not output.is_absolute_path() or not output.ends_with("/build/private-cloud"):
        printerr("Private cloud staging requires an ignored build/private-cloud directory and is forbidden in public Actions")
        quit(1)
        return
    if source.is_empty() or output.is_empty():
        printerr("Explicit private catalog and output directory required")
        quit(1)
        return
    var catalog := SurvivorContestantCatalog.new(source)
    var fingerprint := SurvivorSeasonConfiguration.fingerprint(catalog)
    if not catalog.available or fingerprint != SurvivorSeasonConfiguration.PREVIEW_GAMEPLAY:
        printerr("Approved gameplay catalog fingerprint mismatch")
        quit(1)
        return
    DirAccess.make_dir_recursive_absolute(output)
    var gameplay: Array = []
    for entry: Dictionary in catalog.all():
        var record := {}
        for field: String in SurvivorSeasonConfiguration.GAMEPLAY_FIELDS:
            record[field] = entry[field]
        gameplay.append(record)
    gameplay.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
    var canonical := JSON.stringify(gameplay, "", true)
    var file := FileAccess.open(output.path_join("approved_catalog.sql"), FileAccess.WRITE)
    file.store_string("insert into survivor_private.gameplay_catalogs(fingerprint,canonical) values ('%s','%s') on conflict (fingerprint) do nothing;\n" % [fingerprint, canonical.replace("'", "''")])
    file.close()
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = 11
    for count_value in [2, 3]:
        var division := SurvivorSeasonConfiguration.new()
        division.seed_value = 42
        division.count = count_value
        division.assign(catalog)
        var sim := SeasonSimulation.new("a".repeat(32), ("b" if count_value == 2 else "c").repeat(32), 42)
        sim.configure(division.configuration(catalog, setup), catalog)
        for tick in 120:
            sim.advance("tonsai")
        var partner := ""
        for id: String in sim.camps.tonsai.people:
            if id != "11":
                partner = id
                break
        sim.camps.tonsai.respond("11", partner, "water", sim.tick, "d".repeat(32))
        var snapshot := SaveCodec.encode(sim.snapshot(), 1, 1000)
        if SaveCodec.decode(snapshot).status != "valid":
            printerr("Invalid staged snapshot")
            quit(1)
            return
        file = FileAccess.open(output.path_join("tribes-%d.json" % count_value), FileAccess.WRITE)
        file.store_string(snapshot)
        file.close()
    var technical := SeasonSimulation.new("a".repeat(32), "e".repeat(32), 42)
    file = FileAccess.open(output.path_join("technical.json"), FileAccess.WRITE)
    file.store_string(SaveCodec.encode(technical.snapshot(), 1, 1000))
    file.close()
    print("Approved gameplay catalog and three private RPC fixtures staged")
    quit()
