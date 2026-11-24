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
        errors = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.on("console", lambda msg: errors.append(msg.text) if msg.type == "error" else None)
        now = monotonic()
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_function("Boolean(window.tonsaiMetrics)", timeout=50000)
        startup = round(monotonic() - now, 2)
        page.screenshot(path=config.captures / "spawn.png")
        exercise(page, config.captures)
        steering = {}
        performance = {}
        for name in ("A", "B"):
            tap(page, "controller")
            until(page, lambda m: m["controller"] == name, f"Could not switch to controller {name}")
            steering[name] = sustained_touch(page, config.captures)
            page.evaluate("window.tonsaiView('shore-start')")
            until(page, lambda m: -54.2 < m["x"] < -53.8, "Could not reset performance viewpoint")
            performance[name] = measure_quality(page)
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
            "startup_s": startup,
            "six_animated_characters": performance,
            "conversation_and_two_thumb_controls": "passed",
            "held_forward_swipes_and_cancellation": steering,
            "walk_wade_swim_dive_surface_and_shore_return": "passed",
            "clear_cloudy_and_night_presets": "passed",
        }
        (config.captures / "browser-metrics.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
