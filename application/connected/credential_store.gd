class_name SurvivorCredentialStore
extends RefCounted
## Memory only on Web and native. A future native implementation can use Keychain.

var _tokens: Dictionary = {}

func read() -> Dictionary:
    return _tokens.duplicate()

func replace(value: Dictionary) -> void:
    _tokens = value.duplicate()

func clear() -> void:
    _tokens.clear()
