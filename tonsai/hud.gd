class_name TonsaiCampHud
extends Control

var camp: TonsaiCamp
var touch: CampTouch
var banner: Label
var nearby_button: Button
var nearby_actor: StringName = &""
var run_button: Button
var quality_button: Button
var reset_button: Button
var sensitivity_button: Button
var stats: Label
var dialog: PanelContainer
var speaker: Label
var reply: Label
var topics: Array[Button] = []
var close_button: Button

func _ready() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_IGNORE
    touch = CampTouch.new()
    touch.motor = camp.player
    add_child(touch)
    banner = _label("TONSAI BEACH", 26)
    add_child(banner)
    stats = _label("", 15)
    add_child(stats)
    nearby_button = _button("Talk", func() -> void: camp.begin_talk())
    add_child(nearby_button)
    nearby_button.hide()
    run_button = _button("Walk", _toggle_run)
    add_child(run_button)
    quality_button = _button("Full quality", _toggle_quality)
    add_child(quality_button)
    reset_button = _button("Center camera", camp.player.reset_camera)
    add_child(reset_button)
    sensitivity_button = _button("Look: Medium", _cycle_sensitivity)
    add_child(sensitivity_button)
    dialog = PanelContainer.new()
    var card := StyleBoxFlat.new()
    card.bg_color = Color("#152830ed")
    card.border_color = Color("#8ca89d")
    card.set_border_width_all(1)
    card.set_corner_radius_all(11)
    card.content_margin_left = 17
    card.content_margin_right = 17
    card.content_margin_top = 14
    card.content_margin_bottom = 14
    dialog.add_theme_stylebox_override("panel", card)
    add_child(dialog)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 9)
    dialog.add_child(stack)
    speaker = _label("", 23)
    stack.add_child(speaker)
    reply = _label("", 17)
    reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stack.add_child(reply)
    for topic: StringName in CampSimulation.TOPICS:
        var button := _button(CampSimulation.TOPICS[topic], camp.respond.bind(topic))
        topics.append(button)
        stack.add_child(button)
    close_button = _button("Back to camp", camp.end_talk)
    stack.add_child(close_button)
    dialog.hide()
    get_viewport().size_changed.connect(_layout)
    _layout()

func _layout() -> void:
    var safe := touch.safe.grow(-16.0)
    banner.position = safe.position
    stats.position = safe.position + Vector2(1, 39)
    quality_button.position = Vector2(safe.end.x - 147, safe.position.y)
    reset_button.position = quality_button.position - Vector2(157, 0)
    sensitivity_button.position = reset_button.position - Vector2(157, 0)
    run_button.position = Vector2(safe.end.x - 147, safe.end.y - 54)
    nearby_button.position = Vector2(safe.end.x - 147, safe.end.y - 112)
    var width := minf(445.0, safe.size.x - 24.0)
    dialog.custom_minimum_size.x = width
    dialog.position = Vector2(safe.end.x - width, maxf(safe.position.y + 58, safe.end.y - 313))

func _label(value: String, font_size: int) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color("#f5f5de"))
    label.add_theme_color_override("font_outline_color", Color("#12282c"))
    label.add_theme_constant_override("outline_size", 6)
    label.mouse_filter = MOUSE_FILTER_IGNORE
    return label

func _button(value: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = value
    button.focus_mode = FOCUS_NONE
    button.custom_minimum_size = Vector2(147, 50)
    button.add_theme_font_size_override("font_size", 18)
    for style in ["normal", "hover", "pressed"]:
        var surface := StyleBoxFlat.new()
        surface.bg_color = Color("#1a393ce8") if style == "normal" else Color("#3e5e55")
        surface.border_color = Color("#93ada5aa")
        surface.set_border_width_all(1)
        surface.set_corner_radius_all(7)
        button.add_theme_stylebox_override(style, surface)
    button.pressed.connect(action)
    return button

func refresh() -> void:
    var person := camp.nearby()
    nearby_actor = person.contestant if is_instance_valid(person) else &""
    run_button.text = "Run" if camp.player.run_toggled else "Walk"
    run_button.visible = not camp.player.swimming() and not dialog.visible
    nearby_button.visible = not nearby_actor.is_empty() and not dialog.visible
    if nearby_button.visible:
        nearby_button.text = "Talk to " + String(CampSimulation.CONTESTANTS[person.contestant])

func show_dialog(label: String) -> void:
    speaker.text = label
    reply.text = "What do you want to talk about?"
    nearby_button.hide()
    run_button.hide()
    dialog.show()
    touch.queue_redraw()

func hide_dialog() -> void:
    dialog.hide()
    run_button.show()
    touch.queue_redraw()

func _toggle_run() -> void:
    camp.player.run_toggled = not camp.player.run_toggled
    run_button.text = "Run" if camp.player.run_toggled else "Walk"

func _cycle_sensitivity() -> void:
    var sensitivity := camp.player.sensitivity
    camp.player.sensitivity = .65 if sensitivity > 1.1 else (1.0 if sensitivity < .9 else 1.4)
    var labels := {0.65: "Low", 1.0: "Medium", 1.4: "High"}
    sensitivity_button.text = "Look: " + labels[camp.player.sensitivity]

func _toggle_quality() -> void:
    camp.set_economy(not camp.economical)
    quality_button.text = "Economy" if camp.economical else "Full quality"

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_E:
            camp.begin_talk()
        elif event.physical_keycode == KEY_ESCAPE:
            camp.end_talk()

func control_positions() -> Dictionary:
    var viewport_size := get_viewport_rect().size
    var controls := {}
    for entry in [["talk", nearby_button], ["run", run_button], ["quality", quality_button],
            ["topic", topics[0]], ["close", close_button]]:
        var center: Vector2 = entry[1].get_global_rect().get_center() / viewport_size
        controls[entry[0]] = [center.x, center.y]
    var home := touch.home() / viewport_size
    controls["stick"] = [home.x, home.y]
    return controls
