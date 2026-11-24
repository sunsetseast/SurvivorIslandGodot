class_name SurvivorGameApp
extends Node

enum Screen { MAIN, SLOTS, SETTINGS, SESSION }
const AUTOSAVE_SECONDS := 30
const STORE_PREFIX := "survivor-3a"

var screen := Screen.MAIN
var profile: PlayerProfile
var saves: PersistenceProvider
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
var _slot_mode := false
var _confirm_slot := 0
var _exit_confirmation := false
var _location_ms := 0
var _unload_ms := 0
var _save_usec := 0
var _review_elapsed := 0.0

func _ready() -> void:
    get_tree().auto_accept_quit = false
    var store := LocalDataStore.new(STORE_PREFIX)
    profile = PlayerProfile.new(store)
    saves = LocalSaveProvider.new(store)
    add_child(locations)
    var layer := CanvasLayer.new()
    layer.layer = 5
    add_child(layer)
    _ui = Control.new()
    _ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(_ui)
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
    _main("Local storage is unavailable. Progress may be lost." if not profile.available else "")

func _exit_tree() -> void:
    if _visibility != null:
        var window := JavaScriptBridge.get_interface("window")
        JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _visibility)
        window.removeEventListener("pagehide", _hide)
        window.removeEventListener("pageshow", _show)

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

func _slots(creating: bool) -> void:
    _slot_mode = creating
    _confirm_slot = 0
    _draw_slots()

func _draw_slots(message := "") -> void:
    _menu(Screen.SLOTS, "New Game" if _slot_mode else "Load Game", message)
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
        var pick := _button("slot%d" % index, "Slot %d   %s" % [index, info], action, row)
        pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        pick.disabled = not can_start
        if not entry.status in ["empty", "unavailable"]:
            _button("delete%d" % index, "Confirm delete" if _confirm_slot == index else "Delete",
                _delete.bind(index, String(entry.get("fingerprint", ""))), row)
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
    _draw_slots("Slot deleted." if unchanged and saves.erase(index) else "Slot changed or could not be deleted.")

func _owned(entry: Dictionary) -> bool:
    return entry.status == "valid" and entry.state.player_id == profile.guest_id

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
    var sim := SeasonSimulation.new(profile.guest_id, GameStateData.new_id(), randi())
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
    session = LocalGameSession.new(sim, profile.guest_id)
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
    var result := saves.write(slot, session.checkpoint(), save_revision)
    _save_usec = Time.get_ticks_usec() - started
    if result.status != "valid":
        _status.text = "Save failed · " + String(result.status).replace("_", " ")
        return false
    save_revision = int(result.save_revision)
    _last_checkpoint_tick = tick
    _dirty = false
    _status.text = "Saved to slot %d" % slot
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
    panel.add_child(_stack)
    if not title.is_empty():
        var heading := Label.new()
        heading.text = title
        heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        heading.add_theme_font_size_override("font_size", 31)
        _stack.add_child(heading)
    _status = Label.new()
    _status.text = message
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stack.add_child(_status)
    panel.resized.connect(_position_panel.bind(panel, next == Screen.SESSION))
    _position_panel(panel, next == Screen.SESSION)

func _position_panel(panel: PanelContainer, bottom: bool) -> void:
    var viewport := _ui.size
    var y := viewport.y - panel.size.y - 18.0 if bottom else (viewport.y - panel.size.y) * .5
    panel.position = Vector2((viewport.x - panel.size.x) * .5, y)

func _button(key: String, label: String, action: Callable, parent: Control = null) -> Button:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size = Vector2(110, 47)
    button.add_theme_font_size_override("font_size", 20)
    button.pressed.connect(action)
    (parent if parent != null else _stack).add_child(button)
    _actions[key] = button
    return button
