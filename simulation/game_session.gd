class_name GameSession
extends RefCounted
## An authenticated binding supplies the principal. No actor can grant itself authority.
## Remote implementations will publish the same projections and command results asynchronously.

signal resolved(result: Dictionary)

func submit(_request: Dictionary) -> Dictionary:
    return {"ok": false, "reason": "session_unavailable"}

func view(_location: String) -> Dictionary:
    return {}

func activity(location: String, id: String) -> Dictionary:
    var projected := view(location)
    return projected.get("cast", {}).get(id, {})
