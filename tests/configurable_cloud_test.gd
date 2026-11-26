extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", label)
func _initialize() -> void:
    var stage := OS.get_environment("SURVIVOR_PRIVATE_CLOUD_STAGE")
    var decoded := SaveCodec.decode(FileAccess.get_file_as_string(stage.path_join("tribes-2.json")))
    if decoded.status != "valid":
        printerr("Private validated fixture required")
        quit(1)
        return
    var guest_store := LocalDataStore.new("phase41-guest-" + GameStateData.new_id())
    var account_store := LocalDataStore.new("phase41-account-" + GameStateData.new_id())
    var guest := LocalSaveProvider.new(guest_store)
    var account := LocalSaveProvider.new(account_store)
    check(guest.write(1, decoded.state, 0).status == "valid", "Guest local save")
    var before := guest.inspect(1)
    var cloud := SurvivorCloudSaveService.new(null)
    cloud.bind(account_store, account)
    check(SurvivorCloudSaveService.supports_state(decoded.state), "Configurable cloud supported")
    check(SurvivorCloudSaveService.supports_state({"ruleset":SeasonSimulation.RULESET,"ruleset_version":1}), "Technical cloud retained")
    check(not SurvivorCloudSaveService.supports_state({"ruleset":"unknown","ruleset_version":1}), "Unknown ruleset rejected")
    check(cloud.mark_guest_import(1, decoded.state), "Explicit import is queued")
    check(account.write(1, decoded.state, 0).status == "valid", "Import into empty account slot")
    check(cloud.record(1).get("guest_import") == true, "Import intent retained")
    check(guest.inspect(1).fingerprint == before.fingerprint, "Guest checkpoint preserved")
    var occupied := account.inspect(1)
    check(account.write(1, decoded.state, 0).status == "conflict", "Occupied account slot protected")
    check(account.inspect(1).fingerprint == occupied.fingerprint, "Occupied account checkpoint unchanged")
    cloud.reset(1)
    guest.erase(1)
    account.erase(1)
    cloud.free()
    print("Configurable cloud client: ", failures, " failures")
    quit(1 if failures else 0)
