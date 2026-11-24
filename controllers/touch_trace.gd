extends RefCounted

const BUILD := "2.5 Touch 1"
const DURATION_USEC := 8_000_000
const MAX_EVENTS := 1600
const MAX_FRAMES := 1000

var _started := -1
var _last_yaw := 0.0
var _viewport := Vector2.ZERO
var _events: Array[Array] = []
var _frames: Array[Array] = []

func start(player: CampThirdPerson) -> void:
    _events.clear()
    _frames.clear()
    _viewport = player.get_viewport().get_visible_rect().size
    _last_yaw = player.camera.global_basis.get_euler().y
    _started = Time.get_ticks_usec()

func touch(kind: String, id: int, position: Vector2, owner: String) -> void:
    if _started == -1 or _events.size() >= MAX_EVENTS:
        return
    var time := Time.get_ticks_usec() - _started
    if time < DURATION_USEC:
        _events.append([time, Engine.get_process_frames(), kind, id, owner,
            position.x, position.y, null, null, null, null, null, null])

func drag(event: InputEventScreenDrag, id: int, owner: String, displacement: Vector2, tracked: bool) -> void:
    if _started == -1 or _events.size() >= MAX_EVENTS:
        return
    var time := Time.get_ticks_usec() - _started
    if time < DURATION_USEC:
        _events.append([time, Engine.get_process_frames(), "drag" if tracked else "orphan_drag", id, owner,
            event.position.x, event.position.y, event.relative.x, event.relative.y,
            event.screen_relative.x, event.screen_relative.y, displacement.x, displacement.y])

func frame(player: CampThirdPerson) -> void:
    if _started == -1 or _frames.size() >= MAX_FRAMES:
        return
    var time := Time.get_ticks_usec() - _started
    if time < DURATION_USEC:
        var yaw := player.camera.global_basis.get_euler().y
        _frames.append([time, Engine.get_process_frames(), player.yaw, yaw, angle_difference(_last_yaw, yaw),
            player.travel_heading, "B" if player.controller_b else "A",
            "camera" if player.camera_relative_steering else "stick"])
        _last_yaw = yaw

func finish() -> String:
    _started = -1
    return JSON.stringify({
        "build": BUILD,
        "initial_viewport_size": [_viewport.x, _viewport.y],
        "event_columns": ["us", "frame", "event", "id", "owner", "x", "y",
            "relative_x", "relative_y", "screen_relative_x", "screen_relative_y", "delta_x", "delta_y"],
        "events": _events,
        "frame_columns": ["us", "frame", "target_yaw_rad", "view_yaw_rad", "view_step_rad", "heading_rad",
            "controller", "steering"],
        "frames": _frames,
    })
