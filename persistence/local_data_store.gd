class_name LocalDataStore
extends RefCounted
## Small synchronous records. Native uses user:// and Web uses origin-local
## Storage so a confirmed write does not wait for Godot's delayed IDBFS sync.

var storage_prefix: String
var _browser: JavaScriptObject

func _init(prefix := "survivor-3a") -> void:
    storage_prefix = prefix
    if OS.has_feature("web"):
        # eval converts primitive results. Retrieve the helper as a Web interface.
        JavaScriptBridge.eval("""window.survivorCheckpointStorage ??= Object.freeze({
            readCheckpoint(key) { try { return localStorage.getItem(key) ?? ""; } catch { return null; } },
            writeCheckpoint(key, value) { try { localStorage.setItem(key, value); return true; } catch { return false; } },
            eraseCheckpoint(key) { try { localStorage.removeItem(key); return true; } catch { return false; } }
        })""", true)
        _browser = JavaScriptBridge.get_interface("survivorCheckpointStorage")

func read(key: String) -> Variant:
    var name := storage_prefix + "-" + key
    var path := "user://" + name
    if _browser != null:
        var stored: Variant = _browser.readCheckpoint(name)
        if stored != "" or not FileAccess.file_exists(path):
            return stored
        # Earlier Web builds could fall through to IDBFS. Migrate lazily within
        # the origin after reading and before an ensuing save or delete.
        var legacy: Variant = _read_file(path)
        if legacy is not String or not _browser.writeCheckpoint(name, legacy):
            return null
        _erase_file(path)
        return legacy
    return _read_file(path)

func _read_file(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    if file.get_length() > SaveCodec.MAX_BYTES:
        return "oversized"
    return file.get_as_text()

func write(key: String, value: String) -> bool:
    var name := storage_prefix + "-" + key
    if _browser != null:
        if not _browser.writeCheckpoint(name, value):
            return false
        _erase_file("user://" + name)
        return true
    var file := FileAccess.open("user://" + name, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(value)
    file.flush()
    var ok := file.get_error() == OK
    file.close()
    return ok

func erase(key: String) -> bool:
    var name := storage_prefix + "-" + key
    var path := "user://" + name
    if _browser != null:
        return _erase_file(path) and bool(_browser.eraseCheckpoint(name))
    return _erase_file(path)

func _erase_file(path: String) -> bool:
    return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK
