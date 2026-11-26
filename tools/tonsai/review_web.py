"""Exercise an exported Tonsai build as browser content and capture actual frames."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from math import atan2, cos, hypot, pi, sin
from pathlib import Path
from statistics import median
from threading import Thread
from time import monotonic

from playwright.sync_api import sync_playwright


def metrics(page):
    return page.evaluate("JSON.parse(window.tonsaiMetrics)")


def until(page, test, name, timeout=22):
    deadline = monotonic() + timeout
    while monotonic() < deadline:
        state = metrics(page)
        if test(state):
            return state
        page.wait_for_timeout(150)
    raise AssertionError(f"{name}: {metrics(page)}")


def tap(page, name):
    x, y = metrics(page)["controls"][name]
    page.touchscreen.tap(x * page.viewport_size["width"], y * page.viewport_size["height"])


def exercise(page, captures):
    start = metrics(page)
    assert start["actors"] == 6, start
    if start["nearby"]:
        tap(page, "talk")
        until(page, lambda m: m["dialogue"] == "cirie", "Could not initiate nearby conversation")
        tap(page, "topic")
        until(page, lambda m: "keeping score" in m["reply"], "Reply missing")
        page.screenshot(path=captures / "conversation.png")
        tap(page, "close")
        until(page, lambda m: not m["dialogue"], "Closing conversation did not resume play")
    else:
        raise AssertionError("No nearby contestant at spawn")
    cdp = page.context.new_cdp_session(page)
    width, height = page.viewport_size["width"], page.viewport_size["height"]
    x, y = start["controls"]["stick"]
    left = {"x": x * width, "y": y * height, "id": 1}
    right = {"x": width * .63, "y": height * .5, "id": 2}
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [left, right]})
    left["y"] -= height * .135
    right["x"] += width * .06
    cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [left, right]})
    until(page, lambda m: m["travel"] > start["travel"] + .6 and abs(m["yaw"] - start["yaw"]) > .1,
          "Two-thumb walking and camera orbit failed")
    page.screenshot(path=captures / "explore.png")
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    until(page, lambda m: m["clip"] == "Idle", "Motion persisted after releasing the stick")


def signed_turn(start, end):
    return atan2(sin(end - start), cos(end - start))


def changed_touch_slots(page, captures):
    """Drive the export's real changedTouches handler, including slot corruption."""
    page.evaluate("window.tonsaiView('shore-start')")
    start = until(page, lambda m: -54.2 < m["x"] < -53.8 and abs(signed_turn(pi / 2, m["yaw"])) < .01,
                  "Could not reset the multitouch test")
    assert start["build"] == "2.5 Touch 1", start
    tap(page, "diagnostics")
    tap(page, "touch_trace")
    page.evaluate("""([x, y]) => {
        const canvas = document.querySelector('canvas');
        const box = canvas.getBoundingClientRect();
        const touch = (id, u, v) => new Touch({
            identifier: id, target: canvas, clientX: box.left + u * box.width,
            clientY: box.top + v * box.height
        });
        const emit = (type, changedTouches, touches) => canvas.dispatchEvent(new TouchEvent(type, {
            changedTouches, touches, targetTouches: touches, bubbles: true, cancelable: true
        }));
        const right = touch(1738566071, .66, .49);
        const left = touch(1738566069, x, y);
        const forward = touch(left.identifier, x, y - .13);
        emit('touchstart', [left, right], [left, right]);
        // Only the right finger is in the batch, so the engine subtracts slot 0
        // from the left finger's preceding start even though the right is still.
        emit('touchmove', [right], [left, right]);
        emit('touchmove', [forward, right], [forward, right]);
        emit('touchmove', [right, forward], [forward, right]);
        emit('touchend', [forward], [right]);
        emit('touchmove', [right], [right]);
        emit('touchstart', [left], [left, right]);
        emit('touchmove', [forward], [forward, right]);
        emit('touchmove', [right], [forward, right]);
        window.tonsaiFinishTouchTest = () => {
            const movedRight = touch(right.identifier, .66 + .07 * box.height / box.width, .49);
            emit('touchmove', [movedRight], [forward, movedRight]);
            emit('touchcancel', [movedRight, forward], []);
        };
    }""", start["controls"]["stick"])
    state = until(page, lambda m: m["move_finger"] == 1738566069 and m["look_finger"] == 1738566071
                  and m["travel"] > start["travel"] + .12, "Interleaved touches lost ownership")
    assert abs(signed_turn(start["yaw"], state["yaw"])) < .003, state
    assert abs(signed_turn(start["yaw"] + pi, state["heading"])) < .03, state
    page.evaluate("window.tonsaiFinishTouchTest()")
    state = until(page, lambda m: m["look_finger"] == m["move_finger"] == -1
                  and abs(signed_turn(start["yaw"], m["yaw"])) > .02, "Look drag or touch cancellation was lost")
    assert abs(signed_turn(start["yaw"], state["yaw"]) + .07 * 2.07) < .01, state
    tap(page, "touch_trace")
    dialog = page.get_by_role("dialog", name="Touch diagnostic trace")
    field = dialog.get_by_role("textbox", name="Trace JSON")
    report_text = field.input_value()
    report = json.loads(report_text)
    reports = [dict(zip(report["event_columns"], row)) for row in report["events"]]
    corrupted = [row for row in reports if row["event"] == "drag" and row["owner"] == "look"
                 and hypot(row["delta_x"], row["delta_y"]) < .05 and abs(row["relative_x"]) > 100]
    assert corrupted and report["frames"], report
    page.context.grant_permissions(["clipboard-read", "clipboard-write"])
    dialog.get_by_role("button", name="Copy", exact=True).click()
    dialog.get_by_text("Trace copied").wait_for()
    assert page.evaluate("navigator.clipboard.readText()") == report_text
    page.context.clear_permissions()
    dialog.get_by_role("button", name="Close").click()
    tap(page, "diagnostics")
    (captures / "touch-slot-corruption.json").write_text(report_text + "\n")
    return {
        "corrupted_stationary_look_events": len(corrupted),
        "largest_false_relative_x": max(abs(row["relative_x"]) for row in corrupted),
        "largest_applied_delta_x": max(abs(row["delta_x"]) for row in corrupted),
        "clipboard": "passed",
    }


def sustained_touch(page, captures):
    page.evaluate("window.tonsaiView('shore-start')")
    start = until(page, lambda m: -54.2 < m["x"] < -53.8, "Could not reset travel route")
    cdp = page.context.new_cdp_session(page)
    width, height = page.viewport_size["width"], page.viewport_size["height"]
    x, y = start["controls"]["stick"]
    left = {"x": x * width, "y": y * height, "id": 1}
    right = {"x": width * .65, "y": height * .49, "id": 2}

    def dispatch(kind, *points):
        cdp.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": list(points)})

    dispatch("touchStart", left)
    left["y"] -= height * .14
    dispatch("touchMove", left)
    state = until(page, lambda m: m["travel"] > start["travel"] + .25, "Forward hold failed")
    bearing = state["yaw"]
    forward_x, forward_z = -sin(bearing), -cos(bearing)
    origin = state
    worst_drift = 0.0
    worst_heading_error = 0.0
    min_velocity_alignment = 1.0
    dispatch("touchStart", left, right)
    page.evaluate("window.tonsaiView('trace-start')")
    # Cross the original split with the look finger while the left stick
    # remains held and reverse the swipe repeatedly.
    for fraction in (.89, .66, .42, .30, .61, .86):
        previous = state["yaw"]
        old_x = right["x"]
        right["x"] = round(width * fraction)
        dispatch("touchMove", left, right)
        state = until(page, lambda m: abs(signed_turn(previous, m["yaw"])) > .04,
                      "Orbit lost a held-forward swipe")
        expected = -(right["x"] - old_x) / height * 2.07
        assert abs(signed_turn(previous, state["yaw"]) - expected) < .10, state
        assert state["move_finger"] >= 0 and state["look_finger"] >= 0, state
        assert hypot(state["intent_x"] - forward_x, state["intent_z"] - forward_z) < .04, state
        vx, vz = state["velocity_x"], state["velocity_z"]
        speed = hypot(vx, vz)
        assert speed > .2, state
        min_velocity_alignment = min(min_velocity_alignment, (vx * forward_x + vz * forward_z) / speed)
        worst_heading_error = max(worst_heading_error, abs(signed_turn(bearing + pi, state["heading"])))
        dx, dz = state["x"] - origin["x"], state["z"] - origin["z"]
        worst_drift = max(worst_drift, abs(dx * forward_z - dz * forward_x))
    assert state["travel"] > start["travel"] + .8, state
    assert min_velocity_alignment > .98 and worst_heading_error < .08 and worst_drift < .15, state
    controller = state["controller"]
    page.screenshot(path=captures / f"held-forward-orbit-{controller}.png")
    dispatch("touchCancel")
    until(page, lambda m: m["move_finger"] == m["look_finger"] == -1, "Canceled fingers stayed active")
    page.evaluate("window.tonsaiView('trace-stop')")
    trace = page.evaluate("JSON.parse(window.tonsaiTrace)")
    columns = ("dt", "target_yaw", "target_pitch", "view_yaw", "view_pitch",
               "x", "y", "z", "vx", "vz", "heading", "boom", "obstructed", "swipe_x", "swipe_y",
               "camera_x", "camera_y", "camera_z", "move_finger", "look_finger", "intent_x", "intent_z", "time_usec")
    assert len(trace) >= 6
    assert all(len(frame) == len(columns) for frame in trace)
    (captures / f"camera-frames-{controller}.json").write_text(
        json.dumps({"columns": columns, "frames": trace}, separators=(",", ":")) + "\n"
    )
    return {
        "min_velocity_alignment": min_velocity_alignment,
        "max_heading_error_rad": worst_heading_error,
        "max_cross_track_drift_m": worst_drift,
        "max_rendered_yaw_step_rad": max(abs(signed_turn(a[3], b[3])) for a, b in zip(trace, trace[1:])),
        "median_frame_ms": median(b[-1] - a[-1] for a, b in zip(trace, trace[1:])) / 1000,
        "obstructed_frames": sum(row[12] for row in trace),
    }


def measure_quality(page):
    results = {}
    for name in ("full", "economy"):
        values = []
        for _ in range(3):
            page.wait_for_timeout(450)
            values.append(metrics(page))
        results[name] = {key: median(value[key] for value in values) for key in ("fps", "draws", "primitives")}
        tap(page, "quality")
        until(page, lambda m: m["economy"] == (name == "full"), "Quality switch did not apply")
    return results


def swim(page, captures):
    page.evaluate("window.tonsaiView('shore-start')")
    until(page, lambda m: -54.2 < m["x"] < -53.8, "Shore setup failed")
    page.keyboard.down("w")
    until(page, lambda m: m["locomotion"] == "WADE", "Wading state missing")
    until(page, lambda m: m["pose"] == "Swim" and m["x"] < -72.0, "Stroke state missing", timeout=45)
    page.screenshot(path=captures / "swimming.png")
    page.keyboard.up("w")
    until(page, lambda m: m["pose"] == "Tread", "Treading state missing")
    page.screenshot(path=captures / "treading.png")
    tap(page, "dive")
    submerged = until(page, lambda m: m["locomotion"] == "UNDERWATER" and m["camera_y"] < -.1,
                      "Dive did not put the camera underwater")
    page.keyboard.down("w")
    until(page, lambda m: m["x"] < submerged["x"] - 1.0 and m["pose"] == "Swim",
          "Underwater stroke did not travel")
    page.keyboard.up("w")
    page.screenshot(path=captures / "underwater.png")
    tap(page, "dive")
    until(page, lambda m: m["locomotion"] == "TREAD" and m["camera_y"] > .1, "Surface did not return to treading")
    page.keyboard.down("s")
    until(page, lambda m: m["locomotion"] == "WADE", "Shore return did not wade", timeout=45)
    until(page, lambda m: m["locomotion"] == "LAND", "Shore return did not walk")
    page.keyboard.up("s")


def app_state(page):
    return page.evaluate("JSON.parse(window.survivorApp)")


def app_wait(page, expression):
    page.wait_for_function(
        f"Boolean(window.survivorApp) && ((a) => {expression})(JSON.parse(window.survivorApp))"
    )
    return app_state(page)


def app_tap(page, name):
    state = app_wait(page, f'Boolean(a.actions["{name}"])')
    x, y = state["actions"][name]
    page.touchscreen.tap(x * page.viewport_size["width"], y * page.viewport_size["height"])


def resume_after_reload(page):
    """Exercise the real menu and browser storage with the shipped canvas controls."""
    before = app_wait(page, 'a.screen === "SESSION" && a.knowledge === 1 && a.revision >= 2')
    saved_pose = metrics(page)
    app_tap(page, "save")
    saved = app_wait(page, f"a.revision > {before['revision']}")
    app_tap(page, "menu")
    menu = app_wait(page, 'a.screen === "MAIN"')
    app_tap(page, "settings")
    app_wait(page, 'a.screen === "SETTINGS"')
    app_tap(page, "steering")
    app_wait(page, "a.preferences.camera_steering")
    app_tap(page, "quality")
    app_wait(page, "a.preferences.economy")
    app_tap(page, "sensitivity")
    app_wait(page, "a.preferences.sensitivity > 1")
    page.reload(wait_until="domcontentloaded")
    reloaded = app_wait(page, 'a.screen === "MAIN"')
    assert reloaded["guest"] == before["guest"]
    preferences = reloaded["preferences"]
    assert preferences["camera_steering"] and preferences["economy"] and not preferences["run"], reloaded
    assert abs(preferences["sensitivity"] - 1.4) < .0001, reloaded
    app_tap(page, "continue")
    after = app_wait(page, 'a.screen === "SESSION" && a.knowledge === 1')
    assert after["season"] == before["season"] and after["tick"] >= saved["tick"]
    page.wait_for_function("Boolean(window.tonsaiMetrics)")
    restored = metrics(page)
    assert hypot(restored["x"] - saved_pose["x"], restored["z"] - saved_pose["z"]) < 1.0
    assert abs(signed_turn(restored["heading"], saved_pose["heading"])) < .35
    assert restored["economy"] and restored["controller"] == "B"
    tap(page, "quality")
    until(page, lambda m: not m["economy"], "Could not reset quality after reload")
    tap(page, "steering")
    tap(page, "sensitivity")
    page.wait_for_timeout(330)
    tap(page, "sensitivity")
    app_wait(page, "!a.preferences.camera_steering && a.preferences.sensitivity === 1")
    return {"load_ms": after["location_ms"], "save_usec": saved["save_usec"],
            "sampled_simulation_step_usec": after["step_usec"],
            "unload_ms": menu["unload_ms"], "restored_conversations": after["knowledge"]}


def main():
    args = argparse.ArgumentParser()
    args.add_argument("build", type=Path)
    args.add_argument("captures", type=Path)
    args.add_argument("--chromium")
    args.add_argument("--url", help="Exercise a published copy of the same build")
    config = args.parse_args()
    config.captures.mkdir(parents=True, exist_ok=True)
    handler = partial(SimpleHTTPRequestHandler, directory=config.build.resolve())
    with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server, sync_playwright() as playwright:
        Thread(target=server.serve_forever, daemon=True).start()
        root_url = config.url or f"http://127.0.0.1:{server.server_port}/"
        url = root_url + "?review"
        browser = playwright.chromium.launch(executable_path=config.chromium, args=[
            "--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
        ])
        page = browser.new_page(viewport={"width": 956, "height": 440}, has_touch=True)
        page.set_default_timeout(60000)
        errors = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.on("console", lambda msg: errors.append(msg.text) if msg.type == "error" else None)
        now = monotonic()
        page.goto(url, wait_until="domcontentloaded")
        app_wait(page, 'a.screen === "MAIN"')
        startup = round(monotonic() - now, 2)
        page.screenshot(path=config.captures / "main-menu.png")
        app_tap(page, "new")
        app_wait(page, 'a.screen === "SELECTION" && a.season === ""')
        app_tap(page, "back")
        app_tap(page, "credits")
        app_tap(page, "technical")
        app_wait(page, 'a.screen === "SLOTS"')
        app_tap(page, "slot1")
        page.wait_for_function("Boolean(window.tonsaiMetrics)", timeout=50000)
        page.screenshot(path=config.captures / "spawn.png")
        exercise(page, config.captures)
        lifecycle = resume_after_reload(page)
        steering = {}
        performance = {}
        for name in ("A", "B"):
            tap(page, "controller")
            until(page, lambda m: m["controller"] == name, f"Could not switch to controller {name}")
            steering[name] = sustained_touch(page, config.captures)
            page.evaluate("window.tonsaiView('shore-start')")
            until(page, lambda m: -54.2 < m["x"] < -53.8, "Could not reset performance viewpoint")
            performance[name] = measure_quality(page)
        multitouch = changed_touch_slots(page, config.captures)
        swim(page, config.captures)
        for view in ("coast", "camp", "shelter", "jungle", "well", "cave", "cave-interior", "fire"):
            page.evaluate("view => window.tonsaiView(view)", view)
            page.wait_for_timeout(500)
            page.screenshot(path=config.captures / f"{view}.png")
        tap(page, "sky")
        until(page, lambda m: m["sky"] == "CLOUDY", "Cloudy preset failed")
        page.screenshot(path=config.captures / "fire-cloudy.png")
        tap(page, "sky")
        until(page, lambda m: m["sky"] == "NIGHT", "Night preset failed")
        page.screenshot(path=config.captures / "fire-night.png")
        page.wait_for_timeout(240)
        page.screenshot(path=config.captures / "fire-night-next.png")
        tap(page, "sky")
        until(page, lambda m: m["sky"] == "CLEAR", "Clear preset was not restored")
        assert not errors, errors
        report = {
            "browser": browser.version,
            "device": "Linux Chromium, SwiftShader software WebGL 2, 956×440 CSS px, DPR 1",
            "startup_menu_s": startup,
            "js_heap_bytes": page.evaluate("performance.memory?.usedJSHeapSize ?? null"),
            "reload_and_continue": lifecycle,
            "six_animated_characters": performance,
            "conversation_and_two_thumb_controls": "passed",
            "held_forward_swipes_and_cancellation": steering,
            "changed_touch_slot_corruption": multitouch,
            "walk_wade_swim_dive_surface_and_shore_return": "passed",
            "clear_cloudy_and_night_presets": "passed",
        }
        (config.captures / "browser-metrics.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
