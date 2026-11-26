class_name SurvivorGameApp
extends Node

enum Screen { MAIN, SLOTS, SETTINGS, SESSION, ACCOUNT, MULTIPLAYER, NEW_GAME, CREDITS, SELECTION }
const AUTOSAVE_SECONDS := 30

var screen := Screen.MAIN
var profile: PlayerProfile
var saves: LocalSaveProvider
var identity: SurvivorIdentityService
var auth: SurvivorAuthService
var cloud: SurvivorCloudSaveService
var _accounts: SurvivorAccountMenu
var session: LocalGameSession
var remote: RemoteGameSession
var _room_code: LineEdit
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
var _title_environment: IslandTitleEnvironment
var selection_setup := SurvivorNewSeasonSetup.new()
var contestant_catalog := SurvivorContestantCatalog.new()
var _selection: SurvivorSelectionScreen
var division := SurvivorSeasonConfiguration.new()
var _configured := false
var _manual_pick: Array = []
var _marooning: MarooningPreview
var _brand_panel: VBoxContainer

func _ready() -> void:
    IslandTheme.install()
    if ProjectSettings.get_setting("survivor_diagnostics/enabled", false) and OS.has_feature("web") \
            and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('benchmark')")):
        add_child(load("res://diagnostics/mobile_benchmark.gd").new())
        set_physics_process(false)
        return
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
    _ui.theme = IslandTheme.create()
    layer.add_child(_ui)
    _ui.resized.connect(_layout_menus)
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
    auth.restore_session.call_deferred()
    _main("Local storage is unavailable. Progress may be lost." if not profile.available else "")

func _exit_tree() -> void:
    if remote != null:
        remote.close()
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
            if remote != null:
                remote.close()
            if session == null or _save(false):
                get_tree().quit()
            else:
                _ask_exit()

func _suspend(value: bool) -> void:
    if suspended == value:
        return
    suspended = value
    if remote != null:
        remote.suspend(value)
    if value and _account_scroll != null:
        _account_scroll.cancel_touch()
    if is_instance_valid(_selection):
        _selection.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
        _selection.visible = not value
    if is_instance_valid(_marooning):
        _marooning.touch.cancel()
        _marooning.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
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
    if remote != null:
        remote.poll()
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
    if screen == Screen.SELECTION and is_instance_valid(_selection):
        _review.survivorApp = JSON.stringify({"screen":"SELECTION", "actions":actions,
            "selection":_selection.review_state(), "season":"", "ui_font":_ui.theme.default_font.get_font_name()})
        return
    if is_instance_valid(_marooning):
        _review.survivorApp = JSON.stringify({"screen":"MAROONING", "marooning":_marooning.review_state(), "slot":slot, "revision":save_revision, "season":""})
        return
    if remote != null:
        _review.survivorApp = JSON.stringify({"screen": Screen.keys()[screen], "actions": actions,
            "connected": remote.connected, "active": remote.active, "host_ready":
                screen == Screen.MULTIPLAYER and _actions.start.visible and not _actions.start.disabled})
        return
    if screen == Screen.ACCOUNT or not auth.account.is_empty():
        _review.survivorApp = JSON.stringify({"screen": Screen.keys()[screen], "actions": actions})
        return
    var view := session.view("tonsai") if session != null else {}
    _review.survivorApp = JSON.stringify({"screen": Screen.keys()[screen], "actions": actions,
        "division": division.tribes, "controlled":view.get("controlled", ""), "cast":view.get("cast", {}), "slot": slot, "revision": save_revision, "status": _status.text, "guest": profile.guest_id,
        "preferences": profile.preferences, "season": view.get("season_id", ""),
        "tick": view.get("tick", 0), "knowledge": view.get("knowledge", []).size(),
        "location_ms": _location_ms, "unload_ms": _unload_ms, "save_usec": _save_usec,
        "step_usec": session.last_step_usec if session != null else 0,
        "title_elapsed": _title_environment.elapsed if is_instance_valid(_title_environment) else 0.0,
        "title_camera": var_to_str(_title_environment.camera.position) if is_instance_valid(_title_environment) else "",
        "ui_font": _ui.theme.default_font.get_font_name()})

func _main(message := "") -> void:
    _menu(Screen.MAIN, "", message)
    var latest := 0
    var latest_timestamp := 0
    for index in range(1, LocalSaveProvider.SLOTS + 1):
        var entry := saves.inspect(index)
        if _owned(entry) and int(entry.timestamp) >= latest_timestamp:
            latest = index
            latest_timestamp = int(entry.timestamp)
    var resume := _button("continue", "Continue", _load.bind(latest))
    resume.disabled = latest == 0
    if latest > 0:
        var entry := saves.inspect(latest)
        _status.text = "Day %d · Slot %d" % [entry.state.day, latest] + ("\n" + message if not message.is_empty() else "")

    resume.theme_type_variation = "PrimaryButton"
    _button("new", "New Game", _new_game)
    _button("load", "Load Game", _slots.bind(false))
    _button("settings", "Settings", _settings)
    _button("account", "Account", _accounts.open)
    _button("multiplayer", "Multiplayer Test", _open_multiplayer)
    _button("credits", "Credits", _credits)
    _status.visible = not _status.text.is_empty()
    _build_brand()
    if latest > 0 and message.is_empty():
        resume.tooltip_text = _status.text
        _stack.remove_child(_status)
        _brand_panel.add_child(_status)

func _new_game() -> void:
    _menu(Screen.SELECTION, "", "")
    for child: Node in _ui.get_children():
        _ui.remove_child(child)
        child.queue_free()
    _account_panel = null
    _account_scroll = null
    _selection = SurvivorSelectionScreen.new()
    _selection.catalog = contestant_catalog
    _selection.setup = selection_setup
    _selection.back_requested.connect(_main)
    _selection.confirmed.connect(_season_paths)
    _ui.add_child(_selection)
    _actions = _selection.actions


func _credits() -> void:
    _configured = false
    _menu(Screen.CREDITS, "Credits & notices", "Survivor Island · Development build\n\nTonsai environment: existing project reconstruction and CC0 assets from Poly Haven.\nWater: GodotLearning Stylized Water (CC0).\nAnimation: Quaternius (CC0). Fire: Unity Labs (CC0).\nTypography: Survivant in private builds (rights verification pending). Noto Sans fallback, Google (SIL Open Font License 1.1).\nCamera damping: Phantom Camera (MIT).\n\nSource and license notices: docs/phase2/ASSETS.md, application/presentation/fonts/LICENSE.txt and controllers/third_party/PHANTOM_CAMERA_LICENSE.txt.\nOriginal logo: developer-approved reuse; distribution clearance remains unverified.\nNo commercial affiliation is claimed.")
    _button("technical", "Technical Season Test", _slots.bind(true))
    var notices := Label.new()
    notices.text = FileAccess.get_file_as_string("res://application/presentation/fonts/LICENSE.txt") + "\n" + FileAccess.get_file_as_string("res://controllers/third_party/PHANTOM_CAMERA_LICENSE.txt")
    notices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _stack.add_child(notices)
    _button("back", "Back", _main)

func _build_brand() -> void:
    _brand_panel = VBoxContainer.new()
    _brand_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui.add_child(_brand_panel)
    # Private staging is explicit; the public build uses an elegant text title.
    if ResourceLoader.exists("res://private_brand/logo.png"):
        var logo := TextureRect.new()
        logo.texture = load("res://private_brand/logo.png")
        logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        logo.custom_minimum_size.y = 230
        _brand_panel.add_child(logo)
    else:
        var title := Label.new()
        title.text = "SURVIVOR\nISLAND"
        title.add_theme_font_override("font", IslandTheme.font())
        title.add_theme_font_size_override("font_size", 52)
        title.add_theme_color_override("font_shadow_color", Color("#101e1b"))
        title.add_theme_constant_override("shadow_offset_y", 3)
        _brand_panel.add_child(title)
    _layout_brand()

func _layout_brand() -> void:
    if not is_instance_valid(_brand_panel):
        return
    var factor := _menu_scale()
    _brand_panel.scale = Vector2.ONE * factor
    _brand_panel.size.x = maxf(250, _ui.size.x / factor * .43)
    _brand_panel.position = Vector2(_ui.size.x * .045, (_ui.size.y - 230 * factor) * .5)
    _brand_panel.visible = _ui.size.x / factor > 800

func _open_multiplayer() -> void:
    if auth.account.is_empty() or auth.recovery_pending():
        _accounts.open()
        _status.text = "Sign in to create or join a private session."
        return
    var endpoint := String(ProjectSettings.get_setting("survivor/multiplayer/endpoint", ""))
    if OS.has_feature("web"):
        var location := JavaScriptBridge.get_interface("location")
        if str(location.hostname) in ["localhost", "127.0.0.1"] and endpoint.is_empty():
            endpoint = "ws://" + str(location.host) + "/ws"
    if not endpoint.begins_with("wss://") and not endpoint.begins_with("ws://localhost:") \
            and not endpoint.begins_with("ws://127.0.0.1:"):
        _main("Private multiplayer hosting is unavailable in this build.")
        return
    remote = RemoteGameSession.new(endpoint, auth.multiplayer_access_token)
    remote.changed.connect(_refresh_multiplayer)
    _multiplayer_menu()

func _multiplayer_menu() -> void:
    _menu(Screen.MULTIPLAYER, "Private Multiplayer", remote.status)
    _room_code = LineEdit.new()
    _room_code.placeholder_text = "Join code"
    _room_code.max_length = SurvivorMultiplayerWire.CODE_LENGTH
    _room_code.accessibility_name = "Join code"
    _room_code.virtual_keyboard_show_on_focus = true
    _room_code.gui_input.connect(SurvivorMenuScroll.edit_on_touch.bind(_room_code))
    _room_code.custom_minimum_size.y = 43
    _stack.add_child(_room_code)
    _actions["join_code"] = _room_code
    _button("create", "Create Private Session", remote.request_room.bind("create", {}))
    _button("join", "Join Private Session", _join_private)
    _button("start", "Start Session", remote.request_room.bind("start", {}))
    _button("reconnect", "Reconnect to Session", _reconnect_private)
    _button("back", "Leave Session", _leave_multiplayer)
    _refresh_multiplayer()

func _join_private() -> void:
    var code := _room_code.text.strip_edges()
    if code.length() != SurvivorMultiplayerWire.CODE_LENGTH or not code.is_valid_hex_number(false):
        _status.text = "Enter the 12-character join code."
        return
    remote.request_room("join", {"code": code})

func _reconnect_private() -> void:
    if remote.connected:
        remote.request_room("resume")
    else:
        remote.reconnect()

func _refresh_multiplayer() -> void:
    if remote == null:
        return
    if remote.has_state and locations.camp == null and remote.room.get("started", false):
        _release_title()
        if locations.enter("tonsai", remote, profile):
            _menu(Screen.SESSION, "", remote.status)
            var row := HBoxContainer.new()
            row.alignment = BoxContainer.ALIGNMENT_CENTER
            _stack.add_child(row)
            _button("reconnect", "Reconnect", _reconnect_private, row)
            _button("menu", "Leave Session", _leave_multiplayer, row)
        else:
            _leave_multiplayer("Tonsai could not be loaded.")
            return
    _status.text = remote.status
    _actions.reconnect.visible = screen == Screen.MULTIPLAYER or not remote.connected
    if screen != Screen.MULTIPLAYER:
        return
    var in_room := not remote.room.is_empty()
    _room_code.visible = not in_room
    _actions.create.visible = not in_room
    _actions.join.visible = not in_room
    _actions.create.disabled = not remote.connected
    _actions.join.disabled = not remote.connected
    _actions.start.visible = remote.room.get("host", false) and not remote.room.get("started", false)
    if in_room:
        var connected_names := PackedStringArray()
        for member: Dictionary in remote.room.roster:
            if member.online:
                connected_names.append(SeasonCatalog.TONSAI_CAST[member.contestant])
        _actions.start.disabled = not remote.connected or connected_names.size() != 2
        _status.text += "\nCode " + String(remote.room.code) + " · " + str(connected_names.size()) + "/2 connected"
        if not connected_names.is_empty():
            _status.text += "\n" + ", ".join(connected_names)

func _leave_multiplayer(message := "") -> void:
    var closing := remote
    remote = null
    locations.leave()
    if closing != null:
        closing.close()
    _main(message)

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
    if is_instance_valid(_title_environment):
        _title_environment.set_economy(profile.preferences.economy)
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
    var config := division.configuration(contestant_catalog, selection_setup) if _configured else {}
    if _configured and config.is_empty():
        _status.text = "Invalid season configuration."
        return
    var sim := SeasonSimulation.new(principal, GameStateData.new_id(), int(config.seed) if _configured else randi())
    if _configured:
        sim.configure(config, contestant_catalog)
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
    _release_title()
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
    _selection = null
    screen = next
    _brand_panel = null
    if next in [Screen.SESSION, Screen.SELECTION]:
        _release_title()
    elif not is_instance_valid(_title_environment):
        _title_environment = IslandTitleEnvironment.new()
        _title_environment.economy = profile.preferences.economy
        add_child(_title_environment)
    _actions.clear()
    _slot_sync_labels.clear()
    _account_panel = null
    _account_scroll = null
    for child: Node in _ui.get_children():
        _ui.remove_child(child)
        child.queue_free()
    if next not in [Screen.SESSION, Screen.MAIN]:
        var background := ColorRect.new()
        background.color = Color("#081511a8") if next != Screen.MAIN else Color("#08151138")
        background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _ui.add_child(background)
    var panel := PanelContainer.new()
    _ui.add_child(panel)
    if next == Screen.MAIN:
        panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    elif next == Screen.NEW_GAME:
        panel.add_theme_stylebox_override("panel", IslandTheme.parchment())
    var anchor := Control.PRESET_CENTER_BOTTOM if next == Screen.SESSION else Control.PRESET_CENTER
    panel.set_anchors_preset(anchor)
    _stack = VBoxContainer.new()
    _stack.custom_minimum_size.x = 300 if next == Screen.SESSION else 450
    _stack.add_theme_constant_override("separation", 5 if next == Screen.MAIN else IslandTheme.SPACE)
    if next != Screen.SESSION:
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
        heading.theme_type_variation = "SectionHeading"
        if next == Screen.NEW_GAME:
            heading.add_theme_color_override("font_color", IslandTheme.INK)
            heading.add_theme_constant_override("outline_size", 0)
        if next != Screen.SESSION:
            heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _stack.add_child(heading)
    _status.text = message
    if next == Screen.NEW_GAME:
        _status.add_theme_color_override("font_color", IslandTheme.INK)
        _status.add_theme_constant_override("outline_size", 0)
        _status.add_theme_font_size_override("font_size", 18)
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stack.add_child(_status)
    panel.resized.connect(_position_panel.bind(panel, next == Screen.SESSION))
    _position_panel(panel, next == Screen.SESSION)

func _position_panel(panel: PanelContainer, bottom: bool) -> void:
    var viewport := _ui.size
    var height := _account_visible_height() if panel == _account_panel else viewport.y
    var displayed_size := panel.size * panel.scale
    var inset := Vector2.ZERO
    if OS.has_feature("ios") or OS.has_feature("android"):
        var window := Vector2(DisplayServer.window_get_size()).max(Vector2.ONE)
        var area := Rect2(DisplayServer.get_display_safe_area())
        if area.has_area():
            inset = area.position * viewport / window
            height = minf(height, area.end.y * viewport.y / window.y)
    if screen == Screen.MAIN:
        panel.position = Vector2(_safe_menu_x(viewport.x - displayed_size.x - 32 * _menu_scale() if viewport.x / _menu_scale() > 800 else (viewport.x - displayed_size.x) * .5, displayed_size.x),
            maxf(12, (height - displayed_size.y) * .5))
        return
    var y := height - displayed_size.y - 18.0 if bottom else maxf(inset.y, (height - displayed_size.y + inset.y) * .5)
    panel.position = Vector2(_safe_menu_x((viewport.x - displayed_size.x) * .5, displayed_size.x), y)

func _safe_menu_x(preferred: float, width: float) -> float:
    if OS.has_feature("ios") or OS.has_feature("android"):
        var area := Rect2(DisplayServer.get_display_safe_area())
        var window := Vector2(DisplayServer.window_get_size()).max(Vector2.ONE)
        if area.has_area():
            var left := area.position.x * _ui.size.x / window.x + 12
            var right := area.end.x * _ui.size.x / window.x - 12
            return clampf(preferred, left, maxf(left, right - width))
    return preferred

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
    var content_scale := _menu_scale()
    var width := _ui.size.x / content_scale
    _account_panel.scale = Vector2.ONE * content_scale
    var menu_width := clampf(width * .30, 245, 310) if screen == Screen.MAIN else clampf(width - 88, 140, 560)
    if screen == Screen.NEW_GAME and _actions.has("confirm"):
        menu_width = clampf(width - 88, 140, 900)
    var frame := _account_panel.get_theme_stylebox("panel")
    var vertical_margin := frame.get_content_margin(SIDE_TOP) + frame.get_content_margin(SIDE_BOTTOM)
    var reserve := 32.0 if screen == Screen.MAIN else maxf(64.0, vertical_margin + 24.0)
    _account_scroll.custom_minimum_size = Vector2(menu_width,
        clampf(_account_visible_height() / content_scale - reserve, 90.0, 590.0))
    _account_panel.reset_size()
    _position_panel(_account_panel, false)

func _button(key: String, label: String, action: Callable, parent: Control = null) -> Button:
    var button := Button.new()
    button.text = label.to_upper()
    button.custom_minimum_size = Vector2(110, IslandTheme.TOUCH)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", IslandTheme.BODY)
    button.pressed.connect(action)
    (parent if parent != null else _stack).add_child(button)
    _actions[key] = button
    return button

func _identity_changed() -> void:
    var previous := saves
    var signed_in := not auth.account.is_empty() and not auth.recovery_pending()
    if remote != null and not signed_in:
        _leave_multiplayer("Sign in again to reconnect to your private session.")
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
    elif changed_namespace and screen == Screen.MAIN:
        _main()
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


func _release_title() -> void:
    if is_instance_valid(_title_environment):
        remove_child(_title_environment)
        _title_environment.queue_free()
        _title_environment = null

func _menu_scale() -> float:
    if OS.has_feature("web"):
        return maxf(.1, _ui.size.x / maxf(1, float(JavaScriptBridge.get_interface("window").innerWidth)))
    return maxf(.6, _ui.size.y / 540.0)

func _layout_menus() -> void:
    _update_account_layout()
    _layout_brand()
    for child: Node in _ui.get_children():
        if child is PanelContainer and child != _account_panel:
            _position_panel(child, screen == Screen.SESSION)

func _season_paths() -> void:
    _configured = true
    _menu(Screen.NEW_GAME, "Create Your Season", _season_storage_message())
    _button("standard", "Standard", _standard_formats)
    _button("custom", "Custom", _custom_options)
    _button("back", "Back to Survivor", _new_game)

func _standard_formats() -> void:
    _menu(Screen.NEW_GAME, "Standard Season", "Choose your starting format")
    for format: String in ["Two Tribes", "Three Tribes", "Brains / Brawn / Beauty", "Battle of the Sexes"]:
        _button(format, format, _choose_format.bind(format))
    _button("back", "Back", _season_paths)

func _choose_format(format: String) -> void:
    division.count = 3 if format in ["Three Tribes", "Brains / Brawn / Beauty"] else 2
    division.method = "Balanced" if format in ["Two Tribes", "Three Tribes"] else format
    _reroll()

func _custom_options() -> void:
    _menu(Screen.NEW_GAME, "Custom Season", "Themed assignments enforce compatible tribe counts.")
    _button("count", "%d Tribes" % division.count, _cycle_count)
    _button("method", "Assignment: " + division.method, _cycle_method)
    _button("information", "Information: " + selection_setup.information_mode, _cycle_information)
    _button("rosters", "Assign Tribes", _reroll)
    _button("back", "Back", _season_paths)

func _cycle_count() -> void:
    division.count = 3 if division.count == 2 else 2
    _custom_options()

func _cycle_method() -> void:
    var methods := ["Random", "Balanced", "Brains / Brawn / Beauty", "Battle of the Sexes", "Manual"]
    division.method = methods[(methods.find(division.method) + 1) % methods.size()]
    _custom_options()

func _cycle_information() -> void:
    selection_setup.information_mode = "Immersive" if selection_setup.information_mode == "Detailed" else "Detailed"
    _custom_options()

func _reroll() -> void:
    division.seed_value = randi()
    division.assign(contestant_catalog)
    _manual_pick.clear()
    _tribe_review()

func _tribe_review() -> void:
    _menu(Screen.NEW_GAME, "Confirm Starting Tribes", "Seed %d · %s\n%s\n%s" % [division.seed_value, division.method, "Tap two contestants in different tribes to swap." if division.method == "Manual" else "Review the complete starting roster.", _season_storage_message()])
    var preview := _button("marooning", "Private Marooning Preview · No Save", _open_marooning)
    preview.disabled = division.configuration(contestant_catalog, selection_setup).is_empty()
    var columns := HBoxContainer.new()
    _stack.add_child(columns)
    for i in division.tribes.size():
        var column := VBoxContainer.new()
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        columns.add_child(column)
        var tribe: Dictionary = division.tribes[i]
        _button("name%d" % i, tribe.name + (" · " + tribe.label if not tribe.label.is_empty() else "") + (" · YOUR TRIBE" if selection_setup.selected_id in tribe.members else ""), _cycle_tribe.bind(i, "name"), column)
        var color_button := _button("color%d" % i, "Color: " + tribe.color, _cycle_tribe.bind(i, "color"), column)
        color_button.add_theme_stylebox_override("normal", IslandTheme.wood(Color(tribe.color)))
        var banner := "res://private_brand/tribe-%s.png" % tribe.color
        if ResourceLoader.exists(banner):
            color_button.icon = load(banner)
            color_button.expand_icon = true
            color_button.add_theme_constant_override("icon_max_width", 32)
        for j in tribe.members.size():
            var entry := contestant_catalog.get_by_id(int(tribe.members[j]))
            var row := HBoxContainer.new()
            column.add_child(row)
            if ResourceLoader.exists(entry.portrait_path):
                var portrait := TextureRect.new()
                portrait.texture = load(entry.portrait_path)
                portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                portrait.custom_minimum_size = Vector2(36, 48)
                row.add_child(portrait)
            var button := _button("member%d" % entry.id, entry.name + (" · YOU" if entry.id == selection_setup.selected_id else "") + (" · SELECTED" if _manual_pick == [i, j] else ""), _manual_tap.bind(i, j), row)
            button.add_theme_font_size_override("font_size", 15)
            button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            button.add_theme_color_override("font_disabled_color", Color.WHITE)
            button.disabled = division.method != "Manual"
    if division.method in ["Random", "Balanced"]:
        _button("reroll", "Reroll", _reroll)
    var confirm := _button("confirm", "Confirm Season · Choose Empty Slot", _confirm_season)
    confirm.disabled = division.configuration(contestant_catalog, selection_setup).is_empty()
    _button("back", "Back to Configuration", _custom_options)

    _update_account_layout()

func _cycle_tribe(index: int, field: String) -> void:
    var choices: Array = SurvivorSeasonConfiguration.NAMES if field == "name" else SurvivorSeasonConfiguration.COLORS
    var current: int = choices.find(division.tribes[index][field])
    for offset in range(1, choices.size() + 1):
        var candidate: String = choices[(current + offset) % choices.size()]
        var occupied := false
        for i in division.tribes.size():
            if i != index and (division.tribes[i][field] == candidate or field == "color" and candidate in ["red", "orange"] and division.tribes[i].color in ["red", "orange"]):
                occupied = true
        if not occupied:
            division.tribes[index][field] = candidate
            break
    _tribe_review()

func _manual_tap(tribe: int, member: int) -> void:
    if division.method != "Manual":
        return
    if _manual_pick.size() == 2 and _manual_pick[0] != tribe:
        division._swap(int(_manual_pick[0]), int(_manual_pick[1]), tribe, member)
        _manual_pick.clear()
    else:
        _manual_pick = [tribe, member]
    _tribe_review()

func _confirm_season() -> void:
    if not division.configuration(contestant_catalog, selection_setup).is_empty():
        _slots(true)

func _season_storage_message() -> String:
    return "Account season · Local checkpoints and cloud synchronization" if cloud.store != null else "Guest season · Saved locally. Sign in and explicitly import to sync."

func _open_marooning() -> void:
    var config := division.configuration(contestant_catalog, selection_setup)
    if config.is_empty() or is_instance_valid(_marooning) or session != null:
        return
    _release_title()
    for child: Node in _ui.get_children():
        _ui.remove_child(child)
        child.queue_free()
    _actions.clear()
    _marooning = load("res://marooning/preview.tscn").instantiate()
    _marooning.configuration = config.duplicate(true)
    _marooning.catalog = contestant_catalog
    _marooning.preferences = profile.preferences.duplicate(true)
    _marooning.exited.connect(_close_marooning)
    add_child(_marooning)

func _close_marooning() -> void:
    if not is_instance_valid(_marooning):
        return
    remove_child(_marooning)
    _marooning.queue_free()
    _marooning = null
    _tribe_review()
