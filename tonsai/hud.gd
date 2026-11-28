class_name TonsaiCampHud
extends Control

var camp: TonsaiCamp
var touch: CampTouch
var banner: Label
var nearby_button: Button
var nearby_actor: StringName = &""
var run_button: Button
var dive_button: Button
var sky_button: Button
var quality_button: Button
var reset_button: Button
var sensitivity_button: Button
var steering_button: Button
var controller_button: Button
var diagnostics_button: Button
var trace_button: Button
var diagnostics: Label
var stats: Label
var dialog: PanelContainer
var speaker: Label
var reply: Label
var topics: Array[Button] = []
var close_button: Button
var _trace_ready := false
var condition_button: Button
var rest_button: Button
var drink_button: Button
var eat_button: Button
var water_button: Button
var condition_detail := false
var _period := ""

func _ready() -> void:
    theme = IslandTheme.create()
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_IGNORE
    touch = CampTouch.new()
    touch.motor = camp.player
    add_child(touch)
    var view := camp.session.view("tonsai")
    banner = _label("DAY 1 — CAMP PHASE" if view.get("marooning_season", false) else "TONSAI BEACH", 26)
    if view.get("marooning_season", false):
        banner.add_theme_color_override("font_color", Color(view.tribe_color))
    add_child(banner)
    stats = _label("", 15)
    add_child(stats)
    nearby_button = _button("Talk", func() -> void: camp.begin_talk())
    add_child(nearby_button)
    nearby_button.hide()
    run_button = _button("Walk", _toggle_run)
    add_child(run_button)
    dive_button = _button("Dive", _toggle_dive)
    add_child(dive_button)
    dive_button.hide()
    sky_button = _button("Sky: Clear", _cycle_sky)
    add_child(sky_button)
    quality_button = _button("Full quality", _toggle_quality)
    add_child(quality_button)
    reset_button = _button("Center camera", camp.player.reset_camera)
    add_child(reset_button)
    sensitivity_button = _button("Look: Medium", _cycle_sensitivity)
    add_child(sensitivity_button)
    steering_button = _button("Steer: Stick", _toggle_steering)
    add_child(steering_button)
    controller_button = _button("Controller B", func() -> void: select_controller(not camp.player.controller_b))
    add_child(controller_button)
    diagnostics_button = _button("Diagnostics", _toggle_diagnostics)
    add_child(diagnostics_button)
    trace_button = _button("Record touch", _toggle_touch_trace)
    trace_button.hide()
    add_child(trace_button)
    diagnostics = _label("", 16)
    diagnostics.hide()
    add_child(diagnostics)
    dialog = PanelContainer.new()
    add_child(dialog)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 9)
    dialog.add_child(stack)
    speaker = _label("", 23)
    stack.add_child(speaker)
    reply = _label("", 17)
    reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stack.add_child(reply)
    for topic: String in CampSimulation.TOPICS:
        var button := _button(CampSimulation.TOPICS[topic], camp.respond.bind(StringName(topic)))
        topics.append(button)
        stack.add_child(button)
    close_button = _button("Back to camp", camp.end_talk)
    stack.add_child(close_button)
    dialog.hide()
    condition_button = _button("Condition", func() -> void: condition_detail = not condition_detail)
    rest_button = _button("Rest", func() -> void:
        var view_now := camp.session.view("tonsai")
        var active := camp.local_host.activity("tonsai", view_now.controlled)
        camp.living_action("camp.stop" if active.stage == "occupied" else "camp.start", "shelter"))
    drink_button = _button("Drink at well", func() -> void: camp.living_action("camp.start", "spring"))
    eat_button = _button("Eat coconut", func() -> void: camp.living_action("camp.consume", "shelter", "coconut"))
    water_button = _button("Drink water", func() -> void: camp.living_action("camp.consume", "shelter", "water"))
    for button: Button in [condition_button, rest_button, drink_button, eat_button, water_button]: add_child(button)
    get_viewport().size_changed.connect(_layout)
    _layout()

func _layout() -> void:
    var safe := touch.safe.grow(-16.0)
    banner.position = safe.position
    stats.position = safe.position + Vector2(1, 39)
    condition_button.position = safe.position + Vector2(0, 72)
    rest_button.position = safe.position + Vector2(0, 130)
    drink_button.position = rest_button.position
    eat_button.position = rest_button.position + Vector2(157, 0)
    water_button.position = rest_button.position + Vector2(314, 0)
    quality_button.position = Vector2(safe.end.x - 147, safe.position.y)
    reset_button.position = quality_button.position - Vector2(157, 0)
    sensitivity_button.position = reset_button.position - Vector2(157, 0)
    run_button.position = Vector2(safe.end.x - 147, safe.end.y - 54)
    dive_button.position = run_button.position
    sky_button.position = quality_button.position + Vector2(0, 58)
    steering_button.position = reset_button.position + Vector2(0, 58)
    controller_button.position = sensitivity_button.position + Vector2(0, 58)
    diagnostics_button.position = controller_button.position + Vector2(0, 58)
    trace_button.position = diagnostics_button.position + Vector2(157, 0)
    diagnostics.position = safe.position + Vector2(0, 76)
    nearby_button.position = Vector2(safe.end.x - 147, safe.end.y - 112)
    var width := minf(445.0, safe.size.x - 24.0)
    dialog.custom_minimum_size.x = width
    dialog.position = Vector2(safe.end.x - width, maxf(safe.position.y + 58, safe.end.y - 313))

func _label(value: String, font_size: int) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color.WHITE)
    label.add_theme_color_override("font_outline_color", Color.BLACK)
    label.add_theme_constant_override("outline_size", maxi(2, roundi(font_size * .12)))
    label.mouse_filter = MOUSE_FILTER_IGNORE
    return label

func _button(value: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = value
    button.theme_type_variation = "CompactButton"
    button.focus_mode = FOCUS_NONE
    button.custom_minimum_size = Vector2(147, 50)
    button.add_theme_font_size_override("font_size", 16)
    button.add_theme_constant_override("outline_size", 2)
    button.pressed.connect(action)
    return button

func refresh() -> void:
    var view := camp.session.view("tonsai")
    if view.get("marooning_season", false):
        banner.text = "DAY %d — CAMP PHASE" % int(view.day)
    var condition: Dictionary = view.get("condition", {})
    var living := not condition.is_empty()
    condition_button.visible = living and not dialog.visible
    rest_button.visible = living and not dialog.visible and camp.player.position.distance_to(camp.destinations[&"shelter"]) <= SeasonSimulation.REACH
    drink_button.visible = living and not dialog.visible and camp.player.position.distance_to(camp.destinations[&"spring"]) <= SeasonSimulation.REACH
    eat_button.visible = rest_button.visible
    water_button.visible = rest_button.visible
    sky_button.visible = not living
    if living:
        water_button.disabled = not view.supplies.values().any(func(item: Dictionary) -> bool: return item.type == "water" and int(item.quantity) >= 250)
        water_button.text = "No camp water" if water_button.disabled else "Drink water"
    if living and camp.local_host != null:
        var activity := camp.local_host.activity("tonsai", view.controlled)
        rest_button.text = "Stop resting" if activity.stage == "occupied" and activity.activity == "shelter" else "Rest"
    if living:
        var calendar: Dictionary = view.calendar
        banner.text = "DAY %d · %02d:%02d · %s" % [view.day, int(calendar.seconds) / 3600, int(calendar.seconds) % 3600 / 60, str(calendar.period).capitalize()]
        stats.text = "Food %d   Water %d   Energy %d" % [condition.nutrition / LivingCampRules.SCALE, condition.hydration / LivingCampRules.SCALE, condition.energy / LivingCampRules.SCALE]
        if condition_detail: stats.text += "   Health %d" % (condition.health / LivingCampRules.SCALE)
        if _period != calendar.period:
            _period = calendar.period
            camp.terrain.set_sky_preset(TonsaiTerrain.SkyPreset.NIGHT if _period == "night" else TonsaiTerrain.SkyPreset.CLEAR)
            if _period in ["dawn", "dusk"]:
                camp.terrain.sun.light_energy = .45
                camp.terrain.sun.light_color = Color("#ffc18a")
    var person := camp.nearby()
    nearby_actor = person.contestant if is_instance_valid(person) else &""
    run_button.text = "Run" if camp.player.run_toggled else "Walk"
    run_button.visible = not camp.player.swimming() and not dialog.visible
    dive_button.visible = not dialog.visible and (camp.player.can_dive() or camp.player.dive_requested)
    dive_button.text = "Surface" if camp.player.dive_requested else "Dive"
    nearby_button.visible = not nearby_actor.is_empty() and not dialog.visible
    if nearby_button.visible:
        nearby_button.text = "Talk to " + person.display_name

func show_dialog(label: String) -> void:
    speaker.text = label
    reply.text = "What do you want to talk about?"
    nearby_button.hide()
    run_button.hide()
    dive_button.hide()
    dialog.show()
    touch.queue_redraw()

func hide_dialog() -> void:
    dialog.hide()
    run_button.show()
    touch.queue_redraw()

func _toggle_run() -> void:
    camp.player.run_toggled = not camp.player.run_toggled
    run_button.text = "Run" if camp.player.run_toggled else "Walk"
    camp.remember_preference("run", camp.player.run_toggled)

func _toggle_dive() -> void:
    camp.player.toggle_dive()
    refresh()

func _cycle_sky() -> void:
    camp.terrain.set_sky_preset((camp.terrain.sky_preset + 1) % TonsaiTerrain.SkyPreset.size())
    sky_button.text = "Sky: " + ["Clear", "Cloudy", "Night"][camp.terrain.sky_preset]

func _cycle_sensitivity() -> void:
    var sensitivity := camp.player.sensitivity
    camp.player.sensitivity = .65 if sensitivity > 1.1 else (1.0 if sensitivity < .9 else 1.4)
    camp.remember_preference("sensitivity", camp.player.sensitivity)
    _update_preferences_labels()

func apply_preferences() -> void:
    var preferences := camp.profile.preferences
    camp.player.sensitivity = preferences.sensitivity
    camp.player.camera_relative_steering = preferences.camera_steering
    camp.player.run_toggled = preferences.run
    camp.set_economy(preferences.economy)
    _update_preferences_labels()

func _update_preferences_labels() -> void:
    var labels := {0.65: "Low", 1.0: "Medium", 1.4: "High"}
    sensitivity_button.text = "Look: " + labels[camp.player.sensitivity]
    steering_button.text = "Steer: Camera" if camp.player.camera_relative_steering else "Steer: Stick"
    quality_button.text = "Economy" if camp.economical else "Full quality"

func _toggle_quality() -> void:
    camp.set_economy(not camp.economical)
    camp.remember_preference("economy", camp.economical)
    _update_preferences_labels()

func _toggle_steering() -> void:
    var player := camp.player
    player.camera_relative_steering = not player.camera_relative_steering
    camp.remember_preference("camera_steering", player.camera_relative_steering)
    _update_preferences_labels()

func select_controller(use_b: bool) -> void:
    var player := camp.player
    var running := player.run_toggled
    touch.cancel()
    player.select_controller(use_b)
    player.run_toggled = running
    controller_button.text = "Controller B" if use_b else "Controller A"

func _toggle_diagnostics() -> void:
    diagnostics.visible = not diagnostics.visible
    trace_button.visible = diagnostics.visible

func _toggle_touch_trace() -> void:
    if not _trace_ready:
        touch.trace.start(camp.player)
        _trace_ready = true
        trace_button.text = "Copy trace"
        return
    var report := touch.trace.finish()
    _trace_ready = false
    trace_button.text = "Record touch"
    touch.cancel()
    if not OS.has_feature("web"):
        DisplayServer.clipboard_set(report)
        return
    # A native button gives Safari a trusted tap for writing the clipboard.
    # The text remains selectable if clipboard access is unavailable.
    JavaScriptBridge.eval("""
        (text => {
            const dialog = document.createElement("dialog");
            dialog.setAttribute("aria-label", "Touch diagnostic trace");
            dialog.style.cssText = "width:min(36rem,90vw);box-sizing:border-box;max-height:85dvh;color:#eef4ef;background:#152830;border:1px solid #93ada5;border-radius:8px;font:16px system-ui;padding:16px";
            const tip = document.createElement("p");
            tip.textContent = "Touch diagnostic trace";
            tip.style.marginTop = "0";
            const field = document.createElement("textarea");
            field.setAttribute("aria-label", "Trace JSON");
            field.value = text;
            field.readOnly = true;
            field.style.cssText = "width:100%%;height:28vh;box-sizing:border-box;font-size:16px";
            const copy = document.createElement("button");
            copy.textContent = "Copy";
            copy.autofocus = true;
            const close = document.createElement("button");
            close.textContent = "Close";
            for (const button of [copy, close]) {
                button.style.cssText = "min-height:44px;margin:8px 8px 0 0;padding:0 16px;font:inherit";
            }
            copy.addEventListener("click", async () => {
                try {
                    await navigator.clipboard.writeText(text);
                    tip.textContent = "Trace copied";
                } catch {
                    field.focus();
                    field.select();
                    tip.textContent = "Select the trace text and use Copy";
                }
            });
            close.addEventListener("click", () => dialog.close());
            dialog.addEventListener("close", () => {
                dialog.remove();
                document.querySelector("canvas")?.focus();
            });
            dialog.append(tip, field, copy, close);
            document.body.append(dialog);
            dialog.showModal();
        })(%s)
    """ % JSON.stringify(report), true)

func refresh_diagnostics(frame_delta: float) -> void:
    if not diagnostics.visible:
        return
    var player := camp.player
    var angles := player.camera.global_basis.get_euler()
    var format := ("Touches %d / %d    Swipe %s\nTarget %.1f° / %.1f°    View %.1f° / %.1f°\n"
        + "Intent %s\nVelocity %s    Heading %.1f°\nBoom %.2f m    %s    %.1f ms")
    diagnostics.text = format % [touch.move_finger, touch.look_finger, player.last_swipe,
            rad_to_deg(wrapf(player.yaw, -PI, PI)), rad_to_deg(player.pitch),
            rad_to_deg(angles.y), rad_to_deg(angles.x), player.movement_intent.snapped(Vector3.ONE * .01),
            player.get_real_velocity().snapped(Vector3.ONE * .01), rad_to_deg(player.travel_heading),
            player.camera.position.z, "Obstructed" if player.camera_obstructed() else "Clear",
            frame_delta * 1000.0]

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_E:
            camp.begin_talk()
        elif event.physical_keycode == KEY_ESCAPE:
            camp.end_talk()
        elif event.physical_keycode == KEY_F3:
            _toggle_diagnostics()

func control_positions() -> Dictionary:
    var viewport_size := get_viewport_rect().size
    var controls := {}
    for entry in [["talk", nearby_button], ["run", run_button], ["quality", quality_button],
            ["topic", topics[0]], ["close", close_button], ["dive", dive_button],
            ["sky", sky_button], ["reset", reset_button], ["sensitivity", sensitivity_button],
            ["steering", steering_button], ["controller", controller_button],
            ["diagnostics", diagnostics_button], ["touch_trace", trace_button]]:
        var center: Vector2 = entry[1].get_global_rect().get_center() / viewport_size
        controls[entry[0]] = [center.x, center.y]
    var home := touch.home() / viewport_size
    controls["stick"] = [home.x, home.y]
    return controls
