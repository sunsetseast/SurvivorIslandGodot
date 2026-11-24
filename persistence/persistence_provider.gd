class_name PersistenceProvider
extends RefCounted
## Save revision is an optimistic precondition. Cloud implementations must also
## authenticate ownership and resolve cross-device conflicts before replacing a slot.

func inspect(_slot: int) -> Dictionary:
    return {"status": "unavailable"}

func write(_slot: int, _state: Dictionary, _expected_revision: int) -> Dictionary:
    return {"status": "unavailable"}

func erase(_slot: int) -> bool:
    return false
