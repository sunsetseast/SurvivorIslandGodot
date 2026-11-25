class_name SurvivorIdentityService
extends RefCounted

const GUEST_PREFIX := "survivor-3a"
const ACCOUNT_PREFIX := "survivor-3b-account-"

var guest_store := LocalDataStore.new(GUEST_PREFIX)
var installation_id := ""

func _init() -> void:
    var stored: Variant = guest_store.read("installation")
    if GameStateData.identity(stored):
        installation_id = stored
    else:
        installation_id = GameStateData.new_id()
        guest_store.write("installation", installation_id)

func store_for(account: String) -> LocalDataStore:
    return LocalDataStore.new(ACCOUNT_PREFIX + account) if valid_account(account) else guest_store

func remove_cache(account: String) -> bool:
    if not valid_account(account):
        return false
    var store := store_for(account)
    var saves := LocalSaveProvider.new(store)
    var ok := store.erase("principal")
    for index in range(1, LocalSaveProvider.SLOTS + 1):
        ok = saves.erase(index) and ok
        for generation in 2:
            ok = store.erase("sync-%d-%d" % [index, generation]) and ok
    return ok

func season_principal(store: LocalDataStore) -> String:
    var stored: Variant = store.read("principal")
    if GameStateData.identity(stored):
        return stored
    var principal := GameStateData.new_id()
    return principal if store.write("principal", principal) else ""

static func valid_account(value: String) -> bool:
    return value.length() == 36 and value.split("-").size() == 5 \
        and value.substr(8, 1) == "-" and value.substr(13, 1) == "-" \
        and value.substr(18, 1) == "-" and value.substr(23, 1) == "-" \
        and GameStateData.identity(value.replace("-", ""))
