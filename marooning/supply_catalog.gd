class_name MarooningSupplyCatalog
extends RefCounted
## Gameplay data never depends on imported mesh names.
static func definitions() -> Dictionary:
    var result := {}
    var rows := [
        ["rice", "Rice sack", "food", 2, 3, "kg", 20, "sink", ["food", "campcraft"]],
        ["machete", "Machete", "tool", 0, 2, "tool", 1, "sink", ["campcraft"]],
        ["pot", "Cooking pot", "cooking", 1, 3, "pot", 1, "sink", ["campcraft"]],
        ["water", "Water container", "water", 2, 4, "litre", 10, "float", ["water"]],
        ["fishing", "Fishing kit", "tool", 0, 2, "kit", 1, "float", ["fishing"]],
        ["tarp", "Tarp roll", "shelter", 1, 2, "tarp", 1, "float", ["campcraft"]],
        ["rope", "Rope bundle", "shelter", 0, 6, "metre", 10, "float", ["campcraft"]],
        ["bamboo", "Bamboo bundle", "shelter", 3, 4, "pole", 4, "float", ["campcraft"]],
        ["coconut", "Coconuts", "food", 0, 6, "fruit", 3, "float", ["food"]],
        ["fruit", "Fruit basket", "food", 1, 3, "basket", 1, "float", ["food"]],
        ["wood", "Firewood bundle", "fire", 2, 4, "log", 5, "float", ["firemaking"]],
        ["blanket", "Blanket roll", "shelter", 0, 2, "blanket", 1, "float", ["campcraft"]],
        ["basket", "Empty basket", "storage", 0, 4, "basket", 1, "float", ["storage"]],
        ["cup", "Metal cups", "cooking", 0, 3, "cup", 3, "sink", ["water"]],
        ["tools", "Hand tools", "tool", 1, 2, "kit", 1, "sink", ["campcraft"]]]
    for row: Array in rows:
        result[row[0]] = {"id":row[0], "name":row[1], "category":row[2], "weight":row[3],
            "count":row[4], "unit":row[5], "quantity":row[6], "buoyancy":row[7], "tags":row[8],
            "speed":[.95,.8,.6,.5][row[3]], "pickup_duration":.65 + row[3] * .3,
            "loading_duration":.8 + row[3] * .25, "visual":"res://marooning/supply_visual.gd",
            "camp_inventory":row[0]}
    return result
