class_name SurvivorAccountMenu
extends RefCounted

var _app: SurvivorGameApp
var _mode := ""
var _address := ""
var _fields: Dictionary = {}
var _cooldown_until := 0
var _cloud_items: Array = []
var _profile_data := {}
var _working := false

func _init(app: SurvivorGameApp) -> void:
    _app = app

func open() -> void:
    _address = ""
    if _app.auth.account.is_empty():
        _guest()
    else:
        _dashboard()

func _page(mode: String, title: String, notice := "") -> void:
    _mode = mode
    _fields.clear()
    _app._menu(SurvivorGameApp.Screen.ACCOUNT, title, notice)

func _button(key: String, name: String, action: Callable) -> void:
    var button := _app._button(key, name, action)
    button.custom_minimum_size.y = 42

func _field(key: String, label: String, kind: LineEdit.VirtualKeyboardType, initial := "") -> void:
    var field_label := Label.new()
    field_label.text = label
    _app._stack.add_child(field_label)
    var field := LineEdit.new()
    field.placeholder_text = label
    field.tooltip_text = label
    field.text = initial
    field.accessibility_name = label
    field.virtual_keyboard_type = kind
    field.virtual_keyboard_show_on_focus = true
    field.gui_input.connect(_edit_on_touch.bind(field))
    field.secret = key == "password"
    if OS.has_feature("web") and kind == LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS:
        # Godot 4.7.2's Web keyboard calls setSelectionRange, which HTML
        # input[type=email] rejects. A text input can still request the email keyboard.
        field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
        field.focus_entered.connect(_web_email_keyboard)
    field.max_length = 72 if field.secret else 254
    field.custom_minimum_size.y = 43
    _app._stack.add_child(field)
    _fields[key] = field
    _app._actions[key] = field

func _edit_on_touch(event: InputEvent, field: LineEdit) -> void:
    if event is InputEventScreenTouch and event.pressed:
        field.grab_focus()
        field.edit()
        field.accept_event()

func _web_email_keyboard() -> void:
    JavaScriptBridge.eval("""(() => {
        const canvas = document.getElementById('canvas');
        const input = canvas?.previousElementSibling?.previousElementSibling;
        if (!(input instanceof HTMLInputElement)) return;
        const emailMode = () => {
            if (input.type === 'text') {
                input.inputMode = 'email';
                input.setAttribute('aria-label', 'Email address');
            }
        };
        if (document.activeElement === input) emailMode();
        else input.addEventListener('focus', emailMode, {once: true});
    })()""", true)

func _guest(notice := "") -> void:
    _page("guest", "Survivor Island Account", notice)
    _button("sign_in", "Sign In", _form.bind("login"))
    _button("create_account", "Create Account", _form.bind("register"))
    _button("verify", "Verify Email", _form.bind("verify"))
    _button("recovery", "Forgot Password", _form.bind("recover"))
    _button("recovery_code", "Enter Recovery Code", _form.bind("code"))
    _button("back", "Continue as Guest", _app._main)

func _form(mode: String) -> void:
    var titles := {"login": "Sign In", "register": "Create Account", "verify": "Verify Email",
        "recover": "Forgot Password", "code": "Enter Recovery Code", "new_password": "Set New Password",
        "delete_account": "Delete Account"}
    var hint := ""
    if mode == "delete_account":
        hint = "Permanently delete this account and its cloud saves. Enter your password to confirm."
    elif mode in ["register", "new_password"]:
        hint = "Use 8 to 72 characters."
    elif mode in ["verify", "code"]:
        hint = "Enter the code from your email."
    _page(mode, titles[mode], hint)
    if not mode in ["new_password", "delete_account"]:
        _field("email", "Email address", LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS, _address)
    if mode in ["login", "register", "new_password", "delete_account"]:
        _field("password", "New password" if mode == "new_password" else "Password",
            LineEdit.KEYBOARD_TYPE_PASSWORD)
    if mode in ["verify", "code"]:
        _field("otp", "Email code", LineEdit.KEYBOARD_TYPE_NUMBER)
    _button("submit", "Permanently Delete Account" if mode == "delete_account" else titles[mode], _submit)
    if mode in ["verify", "code"]:
        _button("resend", "Send Another Code", _resend)
    _button("back", "Cancel", _cancel_form)

func _cancel_form() -> void:
    if _working:
        return
    if _app.auth.recovery_pending():
        _app.auth.logout()
    open()

func _text(key: String) -> String:
    var field: LineEdit = _fields.get(key)
    return field.text if field != null else ""

func _begin() -> bool:
    if _working:
        return false
    _working = true
    _app._status.text = "Contacting Survivor Island…"
    return true

func _submit() -> void:
    if not _begin():
        return
    var operation := _mode
    if _fields.has("email"):
        _address = _text("email").strip_edges()
    var password := _text("password")
    for field: LineEdit in _fields.values():
        field.release_focus()
    if _fields.has("password"):
        _fields.password.clear()
    var result: Dictionary
    match operation:
        "login":
            result = await _app.auth.login(_address, password)
        "register":
            result = await _app.auth.register(_address, password)
        "verify", "code":
            result = await _app.auth.verify(_address, _text("otp").strip_edges(), operation == "code")
        "recover":
            result = await _app.auth.resend(_address, true)
        "new_password":
            result = await _app.auth.set_password(password)
        "delete_account":
            var account := _app.auth.account
            result = await _app.auth.delete_account(password)
            if result.ok:
                var removed := _app.identity.remove_cache(account)
                _app.auth.clear()
                _working = false
                _guest("Account deleted." if removed else "Account deleted. Device storage could not be fully cleared.")
                return
        _:
            result = {"ok": false, "code": "invalid_form"}
    _working = false
    if not result.ok:
        _app._status.text = message(String(result.code), int(result.get("status", 0)))
        return
    match operation:
        "register", "recover":
            _cooldown_until = Time.get_ticks_msec() + 60_000
            _form("verify" if operation == "register" else "code")
            _app._status.text = "If email delivery is available for this address, a code will arrive shortly."
        "code":
            _form("new_password")
        "new_password":
            _guest("Password updated. Sign in with your new password.")
        _:
            _address = ""
            _dashboard()

func _resend() -> void:
    if _working:
        return
    if Time.get_ticks_msec() < _cooldown_until:
        _app._status.text = "Please wait before requesting another code."
        return
    if not _begin():
        return
    _address = _text("email").strip_edges()
    var result := await _app.auth.resend(_address, _mode == "code")
    _working = false
    _cooldown_until = Time.get_ticks_msec() + maxi(60, int(result.get("retry_after", 0))) * 1000
    _app._status.text = "If email delivery is available for this address, a code will arrive shortly." \
        if result.ok else message(String(result.code), int(result.get("status", 0)))

func _dashboard(notice := "") -> void:
    _page("dashboard", "Account Profile", notice)
    if _app.auth.account.is_empty():
        _guest(notice)
        return
    var label := Label.new()
    label.text = _app.auth.email
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _app._stack.add_child(label)
    _button("cloud_list", "Cloud Saves", _list)
    _button("guest_import", "Import a Guest Season", _imports)
    _button("edit_profile", "Name & Portable Preferences", _profile)
    _button("sign_out", "Sign Out", _sign_out)
    _button("delete_account", "Delete Account", _form.bind("delete_account"))
    _button("back", "Main Menu", _back_to_game)

func _back_to_game() -> void:
    if not _working:
        _app._main()

func _sign_out() -> void:
    if not _begin():
        return
    var result := await _app.auth.logout()
    _working = false
    _cloud_items.clear()
    _profile_data.clear()
    _guest("Signed out." if result.ok else "Signed out on this device. Server revocation could not be confirmed.")

func _list() -> void:
    if not _begin():
        return
    var result := await _app.cloud.call_data("list")
    _working = false
    if _app.auth.account.is_empty():
        _guest("Sign in again to access cloud saves.")
        return
    _cloud_items = result.get("items", [])
    _page("cloud", "Cloud Saves", "" if result.status == "listed" else message(result.status))
    if result.status == "listed" and _cloud_items.is_empty():
        _app._status.text = "No cloud saves yet."
    for index in _cloud_items.size():
        var row: Dictionary = _cloud_items[index]
        _button("cloud%d" % (index + 1), _metadata(row), _details.bind(row))
    for slot in range(1, LocalSaveProvider.SLOTS + 1):
        var sync := _app.cloud.record(slot)
        var local := _app.saves.inspect(slot)
        if sync.has("blocked") or sync.get("paused", false):
            _button("conflict%d" % slot, "Local slot %d · %s" % [slot,
                message(sync.get("blocked", "local_only"))], _conflict.bind(slot))
        elif local.status == "valid" and int(local.save_revision) != int(sync.get("ack", 0)):
            _info("Local slot %d · waiting to sync" % slot)
    _button("refresh", "Refresh", _list)
    _button("back", "Back", _dashboard)

func _details(row: Dictionary) -> void:
    _page("cloud_detail", "Cloud Season", _metadata(row))
    _button("restore", "Restore Current Revision", _destinations.bind(row, int(row.revision), 0))
    if int(row.revision) > 1:
        _button("previous", "Restore Previous Revision", _destinations.bind(row, int(row.revision) - 1, 0))
    _button("delete_cloud", "Delete Cloud Save", _confirm_delete.bind(row))
    _button("back", "Back", _list)

func _confirm_delete(row: Dictionary) -> void:
    _page("delete_cloud", "Delete Cloud Save", _metadata(row) + "\nDelete this cloud copy and its retained revisions?")
    _button("confirm", "Permanently Delete Cloud Save", _delete_cloud.bind(row))
    _button("back", "Cancel", _details.bind(row))

func _delete_cloud(row: Dictionary) -> void:
    if not _begin():
        return
    var result := await _app.cloud.delete_cloud(row.id, int(row.revision))
    _working = false
    await _list()
    _app._status.text = message(result)

func _imports() -> void:
    _page("import", "Import a Guest Season", "Choose a season from this browser. Its guest checkpoint will stay here.")
    var guest := LocalSaveProvider.new(_app.identity.guest_store)
    for slot in range(1, LocalSaveProvider.SLOTS + 1):
        var value := guest.inspect(slot)
        if value.status == "valid" and value.state.player_id == _app.profile.guest_id:
            _button("guest%d" % slot, "Guest slot %d · %s" % [slot, _metadata(value.state)],
                _destinations.bind({}, 0, slot))
    _button("back", "Back", _dashboard)

func _destinations(row: Dictionary, revision: int, guest: int) -> void:
    _page("destination", "Choose an Empty Slot", "Existing account slots are protected.")
    for slot in range(1, LocalSaveProvider.SLOTS + 1):
        var local := _app.saves.inspect(slot)
        if local.status != "empty":
            _info("Slot %d · %s" % [slot, _metadata(local.state) if local.status == "valid" else local.status])
            continue
        _button("destination%d" % slot, "Use slot %d" % slot,
            _import_slot.bind(guest, slot) if guest > 0 else _restore_slot.bind(row.id, revision, slot))
    _button("back", "Cancel", _imports if guest > 0 else _details.bind(row))

func _import_slot(guest_slot: int, slot: int) -> void:
    if not _begin():
        return
    var guest := LocalSaveProvider.new(_app.identity.guest_store).inspect(guest_slot)
    if guest.status != "valid" or guest.state.player_id != _app.profile.guest_id:
        _working = false
        _app._status.text = "The guest checkpoint is unavailable."
        return
    for index in range(1, LocalSaveProvider.SLOTS + 1):
        var existing := _app.saves.inspect(index)
        if existing.status == "valid" and existing.state.season_id == guest.state.season_id:
            _working = false
            _app._status.text = "This season already exists on this device."
            return
    if _app.saves.inspect(slot).status != "empty":
        _working = false
        _app._status.text = "Choose a slot that is still empty."
        return
    if not _app.cloud.mark_guest_import(slot, guest.state):
        _working = false
        _app._status.text = "Could not record the import in device storage."
        return
    var saved := _app.saves.write(slot, guest.state, 0)
    if saved.status != "valid":
        _app.cloud.reset(slot)
    _working = false
    _dashboard("Guest progress copied to the account cache. Cloud import queued." if saved.status == "valid"
        else "The local copy could not be saved. The guest checkpoint is available.")

func _restore_slot(id: String, revision: int, slot: int) -> void:
    if not _begin():
        return
    var result := await _app.cloud.restore(slot, id, revision)
    _working = false
    if result == "restored":
        _app._main("Cloud season restored to slot %d." % slot)
    else:
        _app._status.text = message(result)

func _conflict(slot: int) -> void:
    var sync := _app.cloud.record(slot)
    var local := _app.saves.inspect(slot)
    _page("conflict", "Resolve Cloud Save", "Local slot %d · %s" % [slot, message(sync.get("blocked", "local_only"))])
    if local.status == "valid":
        _info("Local · " + _metadata(local.state) + " · Checkpoint %d" % int(local.save_revision))
    var remote: Dictionary = sync.get("cloud", {})
    if not remote.is_empty():
        _info("Cloud · " + _metadata(remote))
        _info("This device last confirmed cloud revision %d." % int(sync.get("revision", 0)))
        _button("take_cloud", "Keep Cloud Version", _resolve.bind(slot, "cloud", int(remote.revision)))
        _button("take_local", "Keep Local Version", _resolve.bind(slot, "local", int(remote.revision)))
    if sync.get("blocked") != "already_imported":
        _button("take_both", "Preserve Local as a Separate Cloud Save", _resolve.bind(slot, "both", 0))
    _button("back", "Cancel", _list)

func _resolve(slot: int, choice: String, revision: int) -> void:
    if not _begin():
        return
    var result := await _app.cloud.resolve(slot, choice, revision)
    _working = false
    _dashboard(message(result))

func _profile() -> void:
    if not _begin():
        return
    _profile_data = await _app.cloud.call_data("profile")
    _working = false
    if not _profile_data.has("display_name"):
        _dashboard(message(_profile_data.get("status", "unavailable")))
        return
    _page("profile", "Name & Portable Preferences", "Choose when to apply cloud controls to this device.")
    _field("display_name", "Display name", LineEdit.KEYBOARD_TYPE_DEFAULT, _profile_data.display_name)
    _button("save_name", "Save Display Name", _save_name)
    _button("send_preferences", "Save This Device’s Controls to Account", _save_preferences)
    if _profile_data.preferences is Dictionary:
        _button("get_preferences", "Apply Account Controls on This Device", _apply_preferences)
    _button("back", "Back", _dashboard)

func _save_name() -> void:
    if not _begin():
        return
    var result := await _app.cloud.call_data("name", {"name": _text("display_name")})
    _working = false
    _app._status.text = message(result.status)

func _save_preferences() -> void:
    if not _begin():
        return
    var value := _app.profile.preferences
    var result := await _app.cloud.call_data("settings", {"expected": int(_profile_data.settings_revision),
        "preferences": {"camera_steering": value.camera_steering, "run": value.run,
        "sensitivity": ["0.65", "1.0", "1.4"][[.65, 1.0, 1.4].find(value.sensitivity)]}})
    _working = false
    await _profile()
    _app._status.text = message(result.status)

func _apply_preferences() -> void:
    var prefs: Dictionary = _profile_data.preferences
    var ok := _app.profile.set_preference("camera_steering", bool(prefs.camera_steering))
    ok = _app.profile.set_preference("run", bool(prefs.run)) and ok
    ok = _app.profile.set_preference("sensitivity", String(prefs.sensitivity).to_float()) and ok
    _app._status.text = "Account controls applied." if ok else "Controls could not be saved on this device."

func _metadata(value: Dictionary) -> String:
    return "Day %d · Tick %d · Season %s%s" % [int(value.get("day", 1)), int(value.get("tick", 0)),
        String(value.get("season_id", "")).left(8),
        " · Cloud r%d" % int(value.revision) if value.has("id") else ""]

func _info(value: String) -> void:
    var label := Label.new()
    label.text = value
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _app._stack.add_child(label)

static func message(code: String, http_status := 0) -> String:
    if http_status == 429 or code.begins_with("over_"):
        return "Too many requests. Wait and try again."
    match code:
        "invalid_form": return "Check the email and password requirements."
        "invalid_credentials", "reauthentication_failed": return "The email or password could not be verified."
        "email_not_confirmed": return "Verify your email before signing in."
        "invalid_code", "otp_expired": return "That code is invalid or expired. Request a new one."
        "email_address_not_authorized": return "This development project cannot send email to that address."
        "weak_password": return "Choose a stronger password."
        "same_password": return "Choose a password you have not just used."
        "saved": return "Saved to cloud."
        "deleted": return "Cloud save deleted."
        "restored": return "Local checkpoint restored."
        "queued": return "Local checkpoint queued for cloud sync."
        "conflict": return "Cloud progress changed. Review both versions."
        "missing": return "Cloud copy was removed or is unavailable."
        "capacity": return "All three cloud slots are in use."
        "already_imported": return "This season already exists in the account."
        "already_cached": return "This cloud save already has a local slot."
        "invalid_snapshot": return "The checkpoint could not be validated."
        "save_too_large": return "Checkpoint exceeds the cloud limit. Local progress is saved."
        "pending_offline": return "Saved locally. Cloud sync will retry."
        "local_changed": return "The local checkpoint changed. Choose it again."
        "local_storage": return "Device storage could not confirm the write."
        "restore_incomplete": return "Restore needs to be retried."
        "local_only": return "Stored on this device only."
        "sign_in_required": return "Sign in again first."
        "busy": return "A sync is in progress. Try again shortly."
        _: return "Service unavailable. Try again when connected."
