extends SceneTree
# Runs only in the isolated public simulation test stage. This synthetic cast is
# test data, never a fallback or replacement for the privately approved cast.
var failures := 0
func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", label)
func write_catalog(entries: Array) -> SurvivorContestantCatalog:
    DirAccess.make_dir_recursive_absolute("res://private_cast")
    var file := FileAccess.open(SurvivorContestantCatalog.PRIVATE_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify({"version":1,"entries":entries}))
    file.close()
    return SurvivorContestantCatalog.new()
func _initialize() -> void:
    var entries: Array = []
    for index in 18:
        var attributes := {}
        for group: Dictionary in SurvivorContestantCatalog.GROUPS.values():
            for key: String in group:
                attributes[key] = 5
        var defaults := {}
        for key: String in SurvivorContestantCatalog.DEFAULT_FIELDS:
            match SurvivorContestantCatalog.DEFAULT_FIELDS[key]:
                TYPE_INT: defaults[key] = 0
                TYPE_BOOL: defaults[key] = true
                TYPE_ARRAY: defaults[key] = []
                _: defaults[key] = null
        entries.append({"id":index + 1,"name":"Technical fixture %d" % index,
            "gender":"male" if index % 2 == 0 else "female", "trait":["Physical","Mental","Social"][index / 6],
            "style":"Fixture", "original_season":"Test", "appearance_season":"Test",
            "attributes":attributes,"totals":{"Physical":25,"Mental":25,"Social":25},"defaults":defaults,
            "portrait_path":"res://private_cast/portraits/fixture.webp","model_path":""})
    var catalog := write_catalog(entries)
    var original_hash := SurvivorSeasonConfiguration.fingerprint(catalog)
    var setup := SurvivorNewSeasonSetup.new()
    setup.selected_id = 1
    var division := SurvivorSeasonConfiguration.new()
    division.seed_value = 7
    division.assign(catalog)
    var sim := SeasonSimulation.new("a".repeat(32), "b".repeat(32), 7)
    sim.configure(division.configuration(catalog, setup), catalog)
    var raw := SaveCodec.encode(sim.snapshot(), 1, 100)
    check(SaveCodec.decode(raw).status == "valid", "Baseline fixture round trip")
    for entry: Dictionary in entries:
        entry.portrait_path = "res://private_cast/portraits/replaced.webp"
        entry.model_path = "res://private_cast/models/new.glb"
        entry.appearance_season = "New appearance"
        entry.original_season = "Corrected presentation metadata"
    catalog = write_catalog(entries)
    check(SurvivorSeasonConfiguration.fingerprint(catalog) == original_hash, "Art and appearance do not affect compatibility")
    var decoded := SaveCodec.decode(raw)
    check(decoded.status == "valid", "Existing save survives presentation replacement")
    if decoded.status == "valid":
        check(SeasonSimulation.restore(decoded.state).snapshot() == sim.snapshot(), "Presentation-independent restore")
    entries[0].attributes.strength = 6
    entries[0].totals.Physical = 26
    catalog = write_catalog(entries)
    check(catalog.available and SurvivorSeasonConfiguration.fingerprint(catalog) != original_hash, "Gameplay change detectable")
    check(SaveCodec.decode(raw).status == "corrupt", "Reject incompatible calibration")
    check(SurvivorSeasonConfiguration.migrate_fingerprint(SurvivorSeasonConfiguration.LEGACY_PREVIEW, catalog) == SurvivorSeasonConfiguration.LEGACY_PREVIEW, "Legacy pin cannot accept changed gameplay")
    var identities := {}
    for count_value in [2, 3]:
        for seed_value in range(32):
            var a := SurvivorSeasonConfiguration.new()
            var b := SurvivorSeasonConfiguration.new()
            a.method = "Random"
            b.method = "Random"
            a.count = count_value
            b.count = count_value
            a.seed_value = seed_value
            b.seed_value = seed_value
            a.assign(catalog)
            b.assign(catalog)
            check(a.tribes == b.tribes and a.validate(catalog, 1), "Seeded identities, uniqueness and color exclusion")
            identities[a.tribes[0].name + a.tribes[0].color] = true
            a.tribes[0].name = "Tagi"
            a.tribes[1].name = "Moto"
            if count_value == 3:
                a.tribes[2].name = "Fang"
            a.tribes[0].color = "purple"
            a.tribes[1].color = "orange"
            if count_value == 3:
                a.tribes[2].color = "blue"
            a.seed_value += 100
            a.assign(catalog)
            check(a.tribes[0].name == "Tagi" and a.tribes[1].name == "Moto" and a.tribes[0].color == "purple" and a.tribes[1].color == "orange" and a.validate(catalog, 1), "Custom identities survive membership reroll")
    check(identities.size() > 8, "Initial identities vary across seeds")
    print("Season compatibility hotfix: ", failures, " failures")
    quit(1 if failures else 0)
