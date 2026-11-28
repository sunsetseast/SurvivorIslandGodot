class_name CampResources
extends RefCounted
## Atomic primitives over the season's canonical inventory, never a second store.
const MAX_QUANTITY := 1_000_000_000

static func definition(type: String) -> Dictionary:
    if type == "offshore_fishing_reward": return SurvivorOpeningHandoff.reward_record()
    return MarooningSupplyCatalog.definitions().get(type, {})

static func unit(type: String) -> String:
    if type == "water": return "ml"
    if type == "rice": return "g"
    return str(definition(type).get("unit", ""))

static func migrate(inventory: Dictionary) -> void:
    for items: Dictionary in inventory.values():
        for item: Dictionary in items.values():
            item.quantity = roundi(float(item.quantity) * (1000 if item.unit in ["kg", "litre"] else 1))
            item.unit = unit(item.type)
            item["acquired_quantity"] = int(definition(item.type).quantity) * (1000 if item.unit in ["g", "ml"] else 1)

static func transact(inventory: Dictionary, ledger: Dictionary, season: String, tribe: String, sequence: int, operation: String, args: Dictionary) -> bool:
    if not inventory.has(tribe) or sequence > 4_000_000_000 or sequence != int(ledger.sequence) + 1:
        return false
    var quantity: Variant = args.get("quantity")
    if not GameStateData.integer(quantity, 1, MAX_QUANTITY): return false
    var items: Dictionary = inventory[tribe]
    var instance: String = str(args.get("instance", ""))
    var source: Dictionary = items.get(instance, {})
    var generated := "camp-" + (season + ":" + str(sequence)).sha256_text().left(24)
    match operation:
        "acquire":
            var type := str(args.get("type", ""))
            if items.size() >= 256 or definition(type).is_empty() or items.has(generated) or args.get("source") not in ["camp_gameplay", "development_fixture"]: return false
            items[generated] = {"type":type, "quantity":int(quantity), "unit":unit(type), "source":args.source,
                "definition_version":1, "acquired_quantity":int(quantity)}
        "consume", "adjust", "transfer":
            if source.is_empty() or int(source.quantity) < int(quantity): return false
            if operation == "transfer":
                # Only same-tribe splitting is permitted in Phase 5A.
                if items.size() >= 256 or args.get("destination") != tribe or items.has(generated): return false
                var moved := source.duplicate(true)
                moved.quantity = int(quantity)
                moved.acquired_quantity = int(quantity)
                items[generated] = moved
            source.quantity = int(source.quantity) - int(quantity)
        _: return false
    ledger.sequence = sequence
    return true

static func valid(inventory: Variant, tribes: Dictionary, ledger: Variant) -> bool:
    if inventory is not Dictionary or inventory.size() != tribes.size() or ledger is not Dictionary or not GameStateData.integer(ledger.get("sequence"), 0, 4_000_000_000): return false
    var ids := {}
    for tribe: String in tribes:
        if inventory.get(tribe) is not Dictionary or inventory[tribe].size() > 256: return false
        for id: Variant in inventory[tribe]:
            if id is not String or id.length() > 64 or ids.has(id): return false
            ids[id] = true
            var item: Variant = inventory[tribe][id]
            if item is not Dictionary or definition(str(item.get("type", ""))).is_empty() or item.get("unit") != unit(item.type) \
                    or item.get("definition_version") != 1 or item.get("source") not in ["marooning", "offshore_reward", "camp_gameplay", "development_fixture"] \
                    or not GameStateData.integer(item.get("acquired_quantity"), 0, MAX_QUANTITY) or not GameStateData.integer(item.get("quantity"), 0, item.acquired_quantity): return false
    return true
