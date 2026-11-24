class_name SeasonCatalog
extends RefCounted

# Public technical catalog. Only the existing licensed test rig is bound by the client.
const TRIBES := {"tribe-1": "tonsai", "tribe-2": "camp-2", "tribe-3": "camp-3"}
const LOCATIONS := {"tonsai": "camp", "camp-2": "camp", "camp-3": "camp"}
const TONSAI_CAST := {
    "explorer": "Explorer", "cirie": "Cirie", "yul": "Yul", "parvati": "Parvati",
    "jeremy": "Jeremy", "kelley": "Kelley",
}
const FIRST_ACTIVITIES := {"cirie": "fire", "yul": "shelter", "parvati": "shore", "jeremy": "spring", "kelley": "work"}
const CONTROLLED := "explorer"

static func roster(player_id: String) -> Dictionary:
    var result := {}
    var onscreen := TONSAI_CAST.keys()
    for tribe: String in TRIBES:
        for index in 6:
            var id: String = onscreen[index] if tribe == "tribe-1" else "%s-slot-%d" % [tribe, index + 1]
            result[id] = {
                "catalog": id, "name": TONSAI_CAST.get(id, "Technical slot %d" % (index + 1)),
                "tribe": tribe, "location": TRIBES[tribe],
                "controller": "human" if id == CONTROLLED else "ai",
                "owner": player_id if id == CONTROLLED else "", "status": "active",
            }
    return result
