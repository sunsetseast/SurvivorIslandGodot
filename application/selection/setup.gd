class_name SurvivorNewSeasonSetup
extends RefCounted
## Transient menu choices only. No session, save-slot or season state is created here.

var selected_id: int = 0
const INFORMATION_MODES := ["Detailed", "Immersive"]

var information_mode: String = "Detailed"
var trait_filter: String = "All"
var gender_filter: String = "All"

func validate(catalog: SurvivorContestantCatalog) -> bool:
    return catalog != null and catalog.available and selected_id > 0 \
        and not catalog.get_by_id(selected_id).is_empty() \
        and information_mode in INFORMATION_MODES \
        and trait_filter.to_lower() in ["all", "physical", "mental", "social"] \
        and gender_filter.to_lower() in ["all", "male", "female"]

func ratings_for(entry: Dictionary, is_player: bool) -> Dictionary:
    # Browsing candidates as the prospective protagonist counts as is_player.
    # Fail closed for unknown modes too; only Detailed exposes opponent numbers.
    if not is_player and information_mode != "Detailed":
        return {}
    return {"attributes": entry.get("attributes", {}).duplicate(true),
        "totals": entry.get("totals", {}).duplicate(true)}

func impressions_for(entry: Dictionary) -> Dictionary:
    # Relative category impressions come only from the immutable catalog, never
    # from a season projection, relationship, conversation or strategic intent.
    var strongest: Array[String] = []
    var weakest: Array[String] = []
    var highest := -1
    var lowest := 51
    var totals: Dictionary = entry.get("totals", {})
    for category: String in ["Physical", "Mental", "Social"]:
        var rating := int(totals.get(category, 0))
        if rating > highest:
            highest = rating
            strongest.clear()
        if rating == highest:
            strongest.append(category)
        if rating < lowest:
            lowest = rating
            weakest.clear()
        if rating == lowest:
            weakest.append(category)
    if highest == lowest:
        strongest.clear()
        weakest.clear()
    return {"trait": entry.get("trait", ""), "style": entry.get("style", ""),
        "strengths": strongest, "weaknesses": weakest}
