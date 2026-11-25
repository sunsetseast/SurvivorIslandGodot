class_name SurvivorGameApp
extends Node

enum Screen { MAIN, SLOTS, SETTINGS, SESSION, ACCOUNT }
const AUTOSAVE_SECONDS := 30

var screen := Screen.MAIN
var profile: PlayerProfile
var saves: LocalSaveProvider
var identity: SurvivorIdentityService
var auth: SurvivorAuthService
var cloud: SurvivorCloudSaveService
var _accounts: SurvivorAccountMenu
var session: LocalGameSession
var locations := LocationManager.new()
var slot := 0
var save_revision := 0
var suspended := false
var _last_save_tick := 0
var _last_checkpoint_tick := -1
var _dirty := false
var _ui: Control
var _stack: VBoxContainer
var _status: Label
var _actions := {}
var _review: JavaScriptObject
var _visibility: JavaScriptObject
var _hide: JavaScriptObject
var _show: JavaScriptObject
var _visual_resize: JavaScriptObject
var _account_panel: PanelContainer
var _account_scroll: SurvivorMenuScroll
var _slot_sync_labels: Dictionary = {}
var _slot_mode := false
var _confirm_slot := 0
var _exit_confirmation := false
var _location_ms := 0
var _unload_ms := 0
var _save_usec := 0
var _review_elapsed := 0.0

func _ready() -> void:
    get_tree().auto_accept_quit = false
    identity = SurvivorIdentityService.new()
    profile = PlayerProfile.new(identity.guest_store)
    saves = LocalSaveProvider.new(identity.guest_store)
    var transport := SurvivorSupabaseTransport.new()
    add_child(transport)
    auth = SurvivorAuthService.new(transport)
    add_child(auth)
    cloud = SurvivorCloudSaveService.new(auth)
    add_child(cloud)
    _accounts = SurvivorAccountMenu.new(self)
    auth.changed.connect(_identity_changed)
    cloud.updated.connect(_cloud_updated)
    add_child(locations)
    var layer := CanvasLayer.new()
    layer.layer = 5
    add_child(layer)
    _ui = Control.new()
    _ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(_ui)
    _ui.resized.connect(_update_account_layout)
    if OS.has_feature("web"):
        var window := JavaScriptBridge.get_interface("window")
        if bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('review')")):
            _review = window
        _visibility = JavaScriptBridge.create_callback(_visibility_changed)
        _hide = JavaScriptBridge.create_callback(_page_hiding)
        _show = JavaScriptBridge.create_callback(_page_showing)
        JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _visibility)
        window.addEventListener("pagehide", _hide)
        window.addEventListener("pageshow", _show)
        if window.visualViewport != null:
            _visual_resize = JavaScriptBridge.create_callback(_visual_viewport_changed)
            window.visualViewport.addEventListener("resize", _visual_resize)
    _main("Local storage is unavailable. Progress may be lost." if not profile.available else "")

func _exit_tree() -> void:
    if _visibility != null:
        var window := JavaScriptBridge.get_interface("window")
        JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _visibility)
        window.removeEventListener("pagehide", _hide)
        window.removeEventListener("pageshow", _show)
        if _visual_resize != null:
            window.visualViewport.removeEventListener("resize", _visual_resize)

func _visibility_changed(_args: Array) -> void:
    _suspend(bool(JavaScriptBridge.get_interface("document").hidden))

func _page_hiding(_args: Array) -> void:
    _suspend(true)

func _page_showing(_args: Array) -> void:
    _suspend(bool(JavaScriptBridge.get_interface("document").hidden))

func _notification(what: int) -> void:
    if not is_node_ready():
        return
    match what:
        NOTIFICATION_APPLICATION_PAUSED:
            _suspend(true)
        NOTIFICATION_APPLICATION_RESUMED:
            _suspend(false)
        NOTIFICATION_WM_CLOSE_REQUEST:
            if session == null or _save(false):
                get_tree().quit()
            else:
                _ask_exit()

func _suspend(value: bool) -> void:
    if suspended == value:
        return
    suspended = value
    if value and _account_scroll != null:
        _account_scroll.cancel_touch()
    if locations.camp == null:
        return
    locations.camp.hud.touch.cancel()
    if value:
        _save(false)
    locations.camp.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT

func _physics_process(delta: float) -> void:
    if session == null or suspended:
        return
    session.step(delta)
    var tick := session.current_tick()
    if locations.camp != null and tick - _last_save_tick >= int(AUTOSAVE_SECONDS / SeasonSimulation.TICK_SECONDS):
        _last_save_tick = tick
        _save(false)

func _process(delta: float) -> void:
    if _review == null:
        return
    _review_elapsed += delta
    if _review_elapsed < .15:
        return
    _review_elapsed = 0.0
    var actions := {}
    var size := get_viewport().get_visible_rect().size
    for key: String in _actions:
        var center: Vector2 = _actions[key].get_global_rect().get_center() / size
        actions[key] = [center.x, center.y]
    if screen == Screen.ACCOUNT or not auth.account.is_empty():
        _review.survivorApp = JSON.stringify({"screen": Screen.keys()[screen], "actions": actions})
        return
    var view := session.view("tonsai") if session != null else {}
    _review.survivorApp = JSON.stringify({"screen": Screen.keys()[screen], "actions": actions,
        "slot": slot, "revision": save_revision, "status": _status.text, "guest": profile.guest_id,
        "preferences": profile.preferences, "season": view.get("season_id", ""),
        "tick": view.get("tick", 0), "knowledge": view.get("knowledge", []).size(),
        "location_ms": _location_ms, "unload_ms": _unload_ms, "save_usec": _save_usec,
        "step_usec": session.last_step_usec if session != null else 0})

func _main(message := "") -> void:
    _menu(Screen.MAIN, "Survivor Island", message)
    var latest := 0
    var latest_timestamp := 0
    for index in range(1, LocalSaveProvider.SLOTS + 1):
        var entry := saves.inspect(index)
        if _owned(entry) and int(entry.timestamp) >= latest_timestamp:
            latest = index
            latest_timestamp = int(entry.timestamp)
    var resume := _button("continue", "Continue", _load.bind(latest))
    resume.disabled = latest == 0
    _button("new", "New Game", _slots.bind(true))
    _button("load", "Load Game", _slots.bind(false))
    _button("settings", "Settings", _settings)
    _button("account", "Account & Cloud Saves" if not auth.account.is_empty() else "Account", _accounts.open)

func _slots(creating: bool) -> void:
    _slot_mode = creating
    _confirm_slot = 0
    _draw_slots()

func _draw_slots(message := "") -> void:
    _menu(Screen.SLOTS, "New Game" if _slot_mode else "Load Game", message)
    if not _slot_mode:
        var cloud_button := _button("load_cloud",
            "Cloud Saves" if cloud.store != null else "Sign In for Cloud Saves", _accounts.open_from_load)
        cloud_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    for index in range(1, LocalSaveProvider.SLOTS + 1):
        var entry := saves.inspect(index)
        var row := HBoxContainer.new()
        _stack.add_child(row)
        var info := String(entry.status).capitalize()
        if _owned(entry):
            info = "Day %d · %s · r%d" % [entry.state.day, entry.state.season_id.left(6), entry.save_revision]
            if entry.recovered:
                info += " · recovered"
        elif entry.status == "valid":
            info = "Different guest"
        var can_start: bool = entry.status == "empty" if _slot_mode else _owned(entry)
        var action := _new.bind(index) if _slot_mode else _load.bind(index)
        var column := VBoxContainer.new()
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(column)
        var pick := _button("slot%d" % index, "Slot %d · %s" % [index, info], action, column)
        pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
        pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        pick.disabled = not can_start
        if _owned(entry):
            var badge := Label.new()
            badge.text = cloud.slot_status(index, entry)
            badge.add_theme_font_size_override("font_size", 16)
            column.add_child(badge)
            _slot_sync_labels[index] = badge
        if not entry.status in ["empty", "unavailable"]:
            var erase := _button("delete%d" % index, "Confirm" if _confirm_slot == index else "Delete",
                _delete.bind(index, String(entry.get("fingerprint", ""))), row)
            erase.custom_minimum_size.x = 80
            erase.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    _button("back", "Back", _main)

var _delete_fingerprint := ""

func _delete(index: int, displayed: String) -> void:
    if _confirm_slot != index:
        _confirm_slot = index
        _delete_fingerprint = displayed
        _draw_slots("Confirm deletion of slot %d." % index)
        return
    _confirm_slot = 0
    var unchanged: bool = _delete_fingerprint == saves.inspect(index).get("fingerprint", "")
    var erased := unchanged and cloud.reset(index) and saves.erase(index)
    _draw_slots("Slot deleted." if erased else "Slot changed or could not be deleted.")

func _owned(entry: Dictionary) -> bool:
    return entry.status == "valid" and (cloud.store != null or entry.state.player_id == profile.guest_id)

func _settings() -> void:
    _menu(Screen.SETTINGS, "Settings", "")
    var settings := profile.preferences
    _button("steering", "Steer: " + ("Camera" if settings.camera_steering else "Stick"),
        _preference.bind("camera_steering", not settings.camera_steering))
    var levels := [.65, 1.0, 1.4]
    var current := levels.find(settings.sensitivity)
    _button("sensitivity", "Look: " + ["Low", "Medium", "High"][current],
        _preference.bind("sensitivity", levels[(current + 1) % levels.size()]))
    _button("quality", "Quality: " + ("Economy" if settings.economy else "Full"),
        _preference.bind("economy", not settings.economy))
    _button("speed", "Default pace: " + ("Run" if settings.run else "Walk"),
        _preference.bind("run", not settings.run))
    _button("back", "Back", _main)

func _preference(key: String, value: Variant) -> void:
    var saved := profile.set_preference(key, value)
    _settings()
    if not saved:
        _status.text = "Preference could not be saved."

func _new(index: int) -> void:
    if saves.inspect(index).status != "empty":
        _draw_slots("Choose an empty slot.")
        return
    var principal := profile.guest_id if cloud.store == null else identity.season_principal(cloud.store)
    if principal.is_empty():
        _status.text = "Local storage is unavailable."
        return
    var sim := SeasonSimulation.new(principal, GameStateData.new_id(), randi())
    if _enter(sim, index, 0):
        _save(false)

func _load(index: int) -> void:
    var entry := saves.inspect(index)
    if not _owned(entry):
        _status.text = "This save is unavailable."
        return
    if _enter(SeasonSimulation.restore(entry.state), index, int(entry.save_revision)) and entry.recovered:
        _status.text = "Recovered the previous checkpoint."

func _enter(sim: SeasonSimulation, index: int, revision: int) -> bool:
    session = LocalGameSession.new(sim, sim.player_id)
    slot = index
    save_revision = revision
    _last_save_tick = sim.tick
    _last_checkpoint_tick = sim.tick if revision > 0 else -1
    _dirty = false
    session.resolved.connect(_record_action)
    var start := Time.get_ticks_msec()
    if not locations.enter("tonsai", session, profile):
        session = null
        _main("Tonsai could not be loaded.")
        return false
    _location_ms = Time.get_ticks_msec() - start
    locations.camp.preference_failed.connect(func() -> void: _status.text = "Preference could not be saved.")
    _session_menu()
    return true

func _record_action(result: Dictionary) -> void:
    if result.ok and result.event.type == "conversation_reply":
        _dirty = true
        _save(false)

func _session_menu() -> void:
    _menu(Screen.SESSION, "", "")
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    _stack.add_child(row)
    if _exit_confirmation:
        _button("discard", "Exit without saving", _leave, row)
        _button("stay", "Keep playing", _cancel_exit, row)
        _status.text = "The checkpoint could not be saved."
    else:
        _button("save", "Save", _save.bind(true), row)
        _button("menu", "Main Menu", _exit_session, row)

func _save(manual: bool) -> bool:
    if session == null or not profile.available:
        if is_instance_valid(_status):
            _status.text = "Local storage is unavailable."
        return false
    var tick := session.current_tick()
    if not manual and not _dirty and _last_checkpoint_tick == tick:
        return true
    if locations.camp != null and not locations.camp.checkpoint_player():
        _status.text = "Could not checkpoint this position."
        return false
    var started := Time.get_ticks_usec()
    var active_store := saves
    var result := active_store.write(slot, session.checkpoint(), save_revision)
    _save_usec = Time.get_ticks_usec() - started
    if result.status != "valid":
        _status.text = "Save failed · " + String(result.status).replace("_", " ")
        return false
    save_revision = int(result.save_revision)
    _last_checkpoint_tick = tick
    _dirty = false
    _status.text = "Saved to slot %d" % slot
    if active_store == cloud.saves:
        cloud.schedule(slot, manual)
        if manual:
            _status.text += " · cloud sync pending"
    return true

func _exit_session() -> void:
    if _save(true):
        _leave()
    else:
        _ask_exit()

func _ask_exit() -> void:
    _exit_confirmation = true
    _session_menu()

func _cancel_exit() -> void:
    _exit_confirmation = false
    _session_menu()

func _leave() -> void:
    var started := Time.get_ticks_msec()
    locations.leave()
    _unload_ms = Time.get_ticks_msec() - started
    session = null
    slot = 0
    _exit_confirmation = false
    _main()

func _menu(next: Screen, title: String, message: String) -> void:
    screen = next
    _actions.clear()
    _slot_sync_labels.clear()
    _account_panel = null
    _account_scroll = null
    for child: Node in _ui.get_children():
        _ui.remove_child(child)
        child.queue_free()
    if next != Screen.SESSION:
        var background := ColorRect.new()
        background.color = Color("#172c31")
        background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _ui.add_child(background)
    var panel := PanelContainer.new()
    _ui.add_child(panel)
    var anchor := Control.PRESET_CENTER_BOTTOM if next == Screen.SESSION else Control.PRESET_CENTER
    panel.set_anchors_preset(anchor)
    var surface := StyleBoxFlat.new()
    surface.bg_color = Color("#1a393cee")
    surface.set_corner_radius_all(8)
    surface.content_margin_left = 16
    surface.content_margin_right = 16
    surface.content_margin_top = 8
    surface.content_margin_bottom = 8
    panel.add_theme_stylebox_override("panel", surface)
    _stack = VBoxContainer.new()
    _stack.custom_minimum_size.x = 300 if next == Screen.SESSION else 450
    _stack.add_theme_constant_override("separation", 7)
    if next in [Screen.ACCOUNT, Screen.SLOTS]:
        var scroll := SurvivorMenuScroll.new()
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        scroll.follow_focus = true
        _account_panel = panel
        _account_scroll = scroll
        panel.add_child(scroll)
        _update_account_layout()
        _stack.custom_minimum_size.x = 0
        _stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(_stack)
        _status = Label.new()
        _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    else:
        panel.add_child(_stack)
        _status = Label.new()
    if not title.is_empty():
        var heading := Label.new()
        heading.text = title
        heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        heading.add_theme_font_size_override("font_size", 31)
        if next in [Screen.ACCOUNT, Screen.SLOTS]:
            heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _stack.add_child(heading)
    _status.text = message
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stack.add_child(_status)
    panel.resized.connect(_position_panel.bind(panel, next == Screen.SESSION))
    _position_panel(panel, next == Screen.SESSION)

func _position_panel(panel: PanelContainer, bottom: bool) -> void:
    var viewport := _ui.size
    var height := _account_visible_height() if panel == _account_panel else viewport.y
    var displayed_size := panel.size * panel.scale
    var y := height - displayed_size.y - 18.0 if bottom else maxf(0.0, (height - displayed_size.y) * .5)
    panel.position = Vector2((viewport.x - displayed_size.x) * .5, y)

func _visual_viewport_changed(_args: Array) -> void:
    _update_account_layout()

func _account_visible_height() -> float:
    if _visual_resize != null:
        var window := JavaScriptBridge.get_interface("window")
        return _ui.size.y * clampf(float(window.visualViewport.height) / maxf(1.0, float(window.innerHeight)), 0.2, 1.0)
    return _ui.size.y

func _update_account_layout() -> void:
    if _account_panel == null:
        return
    # Express menu layout in CSS pixels on Web so portrait canvas stretching
    # does not reduce the account text or tap targets to half size.
    var width := _ui.size.x
    if OS.has_feature("web"):
        width = float(JavaScriptBridge.get_interface("window").innerWidth)
    var content_scale := maxf(0.1, _ui.size.x / maxf(1.0, width))
    _account_panel.scale = Vector2.ONE * content_scale
    _account_scroll.custom_minimum_size = Vector2(clampf(width - 56.0, 140.0, 560.0),
        clampf(_account_visible_height() / content_scale - 40.0, 90.0, 590.0))
    _account_panel.reset_size()
    _position_panel(_account_panel, false)

func _button(key: String, label: String, action: Callable, parent: Control = null) -> Button:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size = Vector2(110, 47)
    button.add_theme_font_size_override("font_size", 20)
    button.pressed.connect(action)
    (parent if parent != null else _stack).add_child(button)
    _actions[key] = button
    return button

func _identity_changed() -> void:
    var previous := saves
    var signed_in := not auth.account.is_empty() and not auth.recovery_pending()
    var active_store := identity.store_for(auth.account if signed_in else "")
    var changed_namespace := previous.store.storage_prefix != active_store.storage_prefix
    if session != null and changed_namespace:
        _save(false)
        locations.leave()
        session = null
        slot = 0
    saves = LocalSaveProvider.new(active_store)
    cloud.bind(active_store if signed_in else null, saves if signed_in else null)
    if changed_namespace and screen == Screen.SESSION:
        _main("Session expired. Sign in to resume your account saves.")
    elif changed_namespace and screen == Screen.SLOTS:
        _slots(_slot_mode)
    elif changed_namespace and not signed_in and screen == Screen.ACCOUNT:
        _accounts.account_ended()

func _cloud_updated(index: int, status: String) -> void:
    if screen == Screen.SLOTS and _slot_sync_labels.has(index):
        var entry := saves.inspect(index)
        if _owned(entry):
            _slot_sync_labels[index].text = cloud.slot_status(index, entry)
    if session != null and slot == index and screen == Screen.SESSION:
        _status.text = "Slot %d · %s" % [index, SurvivorAccountMenu.message(status)]
