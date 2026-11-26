class_name SurvivorSelectionScreen
extends Control

signal back_requested
signal confirmed

const GROUPS := SurvivorContestantCatalog.GROUPS
var catalog: SurvivorContestantCatalog
var setup: SurvivorNewSeasonSetup
var actions: Dictionary = {}
var preview: SurvivorCharacterPreview
var _roster: VBoxContainer
var _details: VBoxContainer
var _info_scroll: SurvivorMenuScroll
var _roster_scroll: SurvivorMenuScroll
var _select: Button
var _heading: Label
var _eligible: Array[Dictionary] = []
var _summary := false
var _frame: MarginContainer

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var bg := ColorRect.new()
    bg.color = Color("#211d17")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    _frame = MarginContainer.new()
    add_child(_frame)
    var column := VBoxContainer.new()
    _frame.add_child(column)
    _heading = _label("CHOOSE YOUR SURVIVOR", false, 24)
    _heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_heading)
    var sections := HBoxContainer.new()
    sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(sections)
    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_stretch_ratio = .95
    sections.add_child(left)
    var filters := HBoxContainer.new()
    left.add_child(filters)
    var trait_control := OptionButton.new()
    for value: String in ["All", "Physical", "Mental", "Social"]:
        trait_control.add_item(value)
    trait_control.selected = maxi(0, ["All", "Physical", "Mental", "Social"].find(setup.trait_filter))
    trait_control.custom_minimum_size.y = 44
    trait_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    trait_control.add_theme_font_size_override("font_size", 16)
    filters.add_child(trait_control)
    trait_control.tooltip_text = "Trait classification"
    actions.trait = trait_control
    trait_control.item_selected.connect(func(index: int) -> void:
        setup.trait_filter = trait_control.get_item_text(index)
        _filter())
    var gender := OptionButton.new()
    for value: String in ["All", "Women", "Men"]:
        gender.add_item(value)
    gender.selected = maxi(0, ["All", "female", "male"].find(setup.gender_filter))
    gender.custom_minimum_size.y = 44
    gender.add_theme_font_size_override("font_size", 16)
    filters.add_child(gender)
    gender.tooltip_text = "Gender"
    actions.gender = gender
    gender.item_selected.connect(func(index: int) -> void:
        setup.gender_filter = ["All", "female", "male"][index]
        _filter())
    _roster_scroll = SurvivorMenuScroll.new()
    _roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _roster_scroll.follow_focus = true
    left.add_child(_roster_scroll)
    _roster = VBoxContainer.new()
    _roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _roster_scroll.add_child(_roster)
    preview = SurvivorCharacterPreview.new()
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview.size_flags_stretch_ratio = 1.0
    sections.add_child(preview)
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", _parchment())
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_stretch_ratio = 1.3
    sections.add_child(panel)
    _info_scroll = SurvivorMenuScroll.new()
    _info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _info_scroll.follow_focus = true
    panel.add_child(_info_scroll)
    _details = VBoxContainer.new()
    _details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _info_scroll.add_child(_details)
    var bottom := HBoxContainer.new()
    column.add_child(bottom)
    _button("back", "BACK", func() -> void: back_requested.emit(), bottom)
    _button("random", "RANDOM", random_select, bottom)
    _select = _button("select", "SELECT SURVIVOR", confirm_selection, bottom)
    resized.connect(_layout)
    _frame.resized.connect(_layout.call_deferred)
    _layout()
    _filter()
    _layout.call_deferred()

func _layout() -> void:
    if _frame == null:
        return
    var factor := 1.0
    if OS.has_feature("web"):
        factor = size.x / maxf(1.0, float(JavaScriptBridge.get_interface("window").innerWidth))
    else:
        factor = maxf(.6, size.y / 540.0)
    _frame.scale = Vector2.ONE * factor
    _frame.size = size / factor
    var side := 12
    if OS.has_feature("ios") or OS.has_feature("android"):
        var area := Rect2(DisplayServer.get_display_safe_area())
        var window := Vector2(DisplayServer.window_get_size()).max(Vector2.ONE)
        side = maxi(side, int(maxf(area.position.x, window.x - area.end.x) * size.x / window.x / factor) + 8)
    for key: String in ["margin_left", "margin_right"]:
        _frame.add_theme_constant_override(key, side)
    _frame.add_theme_constant_override("margin_top", 6)
    _frame.add_theme_constant_override("margin_bottom", 8)

func _parchment() -> StyleBox:
    if not ResourceLoader.exists("res://private_brand/parch-portrait.png"):
        return IslandTheme.surface(Color("#e7c790"), Color("#855c31"), 12)
    var box := StyleBoxTexture.new()
    box.texture = load("res://private_brand/parch-portrait.png")
    for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
        box.set_texture_margin(side, 30)
        box.set_content_margin(side, 26)
    box.set_content_margin(SIDE_TOP, 32)
    return box

func _label(value: String, ink := true, font_size := 17) -> Label:
    var label := Label.new()
    label.text = value
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    if ink:
        label.add_theme_color_override("font_color", IslandTheme.INK)
        label.add_theme_constant_override("outline_size", 0)
    return label

func _button(key: String, text: String, callback: Callable, parent: Control) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size.y = 46
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.theme_type_variation = "CompactButton"
    button.add_theme_font_size_override("font_size", 17)
    button.pressed.connect(callback)
    parent.add_child(button)
    actions[key] = button
    return button

func _clear(node: Node) -> void:
    for child: Node in node.get_children():
        node.remove_child(child)
        child.queue_free()

func _filter() -> void:
    _eligible = catalog.eligible(setup.trait_filter, setup.gender_filter)
    if not _eligible.any(func(entry: Dictionary) -> bool: return int(entry.id) == setup.selected_id):
        setup.selected_id = int(_eligible[0].id) if not _eligible.is_empty() else 0
    _summary = false
    _draw_roster()
    _show_selected()

func _draw_roster() -> void:
    _clear(_roster)
    for key: String in actions.keys():
        if key.begins_with("cast_"):
            actions.erase(key)
    for entry: Dictionary in _eligible:
        var row := _button("cast_%d" % int(entry.id), entry.name, choose.bind(int(entry.id)), _roster)
        row.text = ""
        row.tooltip_text = entry.name
        row.custom_minimum_size.y = 62
        row.add_theme_stylebox_override("normal", IslandTheme.wood(IslandTheme.GOLD if int(entry.id) == setup.selected_id else Color.WHITE))
        var inset := MarginContainer.new()
        inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(inset)
        inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        for side: String in ["margin_left", "margin_right"]:
            inset.add_theme_constant_override(side, 14)
        inset.add_theme_constant_override("margin_top", 5)
        inset.add_theme_constant_override("margin_bottom", 5)
        var content := HBoxContainer.new()
        content.mouse_filter = Control.MOUSE_FILTER_IGNORE
        inset.add_child(content)
        var path := str(entry.get("portrait_path", ""))
        if not path.is_empty() and ResourceLoader.exists(path):
            var portrait := TextureRect.new()
            portrait.texture = load(path)
            portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            portrait.custom_minimum_size.x = 40
            portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
            content.add_child(portrait)
        var name_label := _label(("• " if int(entry.id) == setup.selected_id else "") + str(entry.name), false, 17)
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        content.add_child(name_label)
    _select.disabled = _eligible.is_empty()
    actions.random.disabled = _eligible.is_empty()

func choose(id: int) -> void:
    if not _eligible.any(func(entry: Dictionary) -> bool: return int(entry.id) == id):
        return
    setup.selected_id = id
    _summary = false
    _draw_roster()
    _show_selected()

func random_select() -> void:
    if not _eligible.is_empty():
        choose(int(_eligible.pick_random().id))
        _reveal_selected.call_deferred()

func _reveal_selected() -> void:
    var row: Control = actions.get("cast_%d" % setup.selected_id)
    if is_instance_valid(row) and _roster_scroll.is_ancestor_of(row):
        _roster_scroll.ensure_control_visible(row)

func _show_selected() -> void:
    _summary = false
    actions.erase("mode")
    actions.erase("inspect")
    _clear(_details)
    _info_scroll.scroll_vertical = 0
    var entry := catalog.get_by_id(setup.selected_id)
    preview.show_contestant(entry)
    _heading.text = "CHOOSE YOUR SURVIVOR"
    if entry.is_empty():
        if catalog.available:
            _details.add_child(_label("No contestants match these filters", true, 24))
            return
        _details.add_child(_label("Private contestant catalog unavailable", true, 24))
        _details.add_child(_label("This public build excludes restricted cast content. The authorized private preview includes the established cast and portraits."))
        return
    _details.add_child(_label(entry.name, true, 26))
    _details.add_child(_label("Debut · " + str(entry.original_season)))
    _details.add_child(_label("Appearance · " + str(entry.appearance_season)))
    _details.add_child(_label(str(entry.trait) + " · " + str(entry.style)))
    for category: String in ["Physical", "Mental", "Social"]:
        _details.add_child(_label("%s   %d / 50" % [category, int(entry.totals[category])]))
        var bar := ProgressBar.new()
        bar.max_value = 50
        bar.value = float(entry.totals[category])
        bar.show_percentage = false
        bar.custom_minimum_size.y = 8
        _details.add_child(bar)
    _details.add_child(_label("INFORMATION MODE", true, 18))
    var mode := OptionButton.new()
    mode.add_item("Detailed")
    mode.add_item("Immersive")
    mode.selected = 1 if setup.information_mode == "Immersive" else 0
    mode.custom_minimum_size.y = 44
    mode.add_theme_font_size_override("font_size", 17)
    mode.item_selected.connect(func(index: int) -> void: setup.information_mode = ["Detailed", "Immersive"][index])
    _details.add_child(mode)
    actions.mode = mode
    _details.add_child(_label("Your own ratings remain available in both modes. Immersive will show general impressions of opponents and withhold their detailed strategic tendencies."))
    for group: String in GROUPS:
        _details.add_child(_label(group.to_upper(), true, 20))
        for field: String in GROUPS[group]:
            _details.add_child(_label("%s   %d / 10" % [GROUPS[group][field], int(entry.attributes[field])]))
    _details.add_child(_label("Ratings are gameplay interpretations, not objective judgments about real people. Tendencies and camp-work avoidance are not universal positive abilities."))

func confirm_selection() -> void:
    var entry := catalog.get_by_id(setup.selected_id)
    if not setup.validate(catalog) or entry.is_empty() or not _eligible.any(func(item: Dictionary) -> bool: return int(item.id) == setup.selected_id):
        return
    _summary = true
    _heading.text = "SURVIVOR SELECTED"
    actions.erase("mode")
    actions.erase("inspect")
    _clear(_details)
    _info_scroll.scroll_vertical = 0
    _details.add_child(_label(entry.name, true, 26))
    _details.add_child(_label("Ready for Phase 4C", true, 22))
    _details.add_child(_label("Catalog ID · %d\nInformation · %s\n\nSelection retained for season configuration. Custom season creation is not implemented yet. No season or save has been created." % [setup.selected_id, setup.information_mode]))
    _button("inspect", "INSPECT ATTRIBUTES", _show_selected, _details)
    confirmed.emit()

func _normalized_rect(control: Control) -> Array:
    var rect := control.get_global_rect()
    var viewport := get_viewport_rect().size
    return [rect.position.x / viewport.x, rect.position.y / viewport.y,
        rect.size.x / viewport.x, rect.size.y / viewport.y]

func review_state() -> Dictionary:
    var ids: Array[int] = []
    for entry: Dictionary in _eligible:
        ids.append(int(entry.id))
    return {"selected_id":setup.selected_id, "eligible":ids, "mode":setup.information_mode, "summary":_summary, "preview":preview.status_text, "roster_rect":_normalized_rect(_roster_scroll),
        "details_rect":_normalized_rect(_info_scroll), "roster_offset":_roster_scroll.scroll_vertical,
        "details_offset":_info_scroll.scroll_vertical, "model_count":int(preview._pivot != null)}

func _exit_tree() -> void:
    if is_instance_valid(preview):
        preview.teardown()
