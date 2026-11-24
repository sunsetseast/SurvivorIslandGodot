"""Exercise an exported Tonsai build as browser content and capture actual frames."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
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
    tap(page, "quality")
    page.wait_for_timeout(550)
    economy = [metrics(page)]
    for _ in range(4):
        page.wait_for_timeout(400)
        economy.append(metrics(page))
    tap(page, "quality")
    page.wait_for_timeout(550)
    full = [metrics(page)]
    for _ in range(4):
        page.wait_for_timeout(400)
        full.append(metrics(page))
    return {
        name: {metric: median(entry[metric] for entry in samples) for metric in ("fps", "draws", "primitives")}
        for name, samples in (("economy", economy), ("full", full))
    }


def swim(page, captures):
    page.evaluate("window.tonsaiView('shore-start')")
    until(page, lambda m: -54.2 < m["x"] < -53.8, "Shore setup failed")
    page.keyboard.down("w")
    until(page, lambda m: m["locomotion"] == "WADE", "Wading state missing")
    until(page, lambda m: m["pose"] == "Swim" and m["x"] < -67.0, "Stroke state missing", timeout=45)
    page.screenshot(path=captures / "swimming.png")
    page.keyboard.up("w")
    until(page, lambda m: m["pose"] == "Tread", "Treading state missing")
    page.screenshot(path=captures / "treading.png")
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
        performance = exercise(page, config.captures)
        swim(page, config.captures)
        for view in ("coast", "camp", "shelter", "jungle", "well", "cave", "cave-interior"):
            page.evaluate("view => window.tonsaiView(view)", view)
            page.wait_for_timeout(500)
            page.screenshot(path=config.captures / f"{view}.png")
        assert not errors, errors
        report = {
            "browser": browser.version,
            "device": "Linux Chromium, SwiftShader software WebGL 2, 956×440 CSS px, DPR 1",
            "startup_s": startup,
            "six_animated_characters": performance,
            "conversation_and_two_thumb_controls": "passed",
            "walk_wade_swim_tread_and_shore_return": "passed",
        }
        (config.captures / "browser-metrics.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
