class_name LocalDataStore
extends RefCounted
## Small synchronous records. Native uses user:// and Web uses origin-local
## Storage so a confirmed write does not wait for Godot's delayed IDBFS sync.

var storage_prefix: String
var _browser: JavaScriptObject

func _init(prefix := "survivor-3a") -> void:
    storage_prefix = prefix
    if OS.has_feature("web"):
        _browser = JavaScriptBridge.eval("""({
            get(key) { try { return localStorage.getItem(key) ?? ""; } catch { return null; } },
            put(key, value) { try { localStorage.setItem(key, value); return true; } catch { return false; } },
            erase(key) { try { localStorage.removeItem(key); return true; } catch { return false; } }
        })""", true)

func read(key: String) -> Variant:
    var name := storage_prefix + "-" + key
    if _browser != null:
        return _browser.get(name)
    var path := "user://" + name
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
        return bool(_browser.put(name, value))
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
    if _browser != null:
        return bool(_browser.erase(name))
    var path := "user://" + name
    return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK
