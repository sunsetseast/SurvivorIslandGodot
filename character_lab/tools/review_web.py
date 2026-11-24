"""Capture the actual Godot Web lab and exercise the standalone build in Chromium."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
from statistics import median
from threading import Thread
from time import monotonic

from playwright.sync_api import sync_playwright

VIEWS = (
    "face-front", "face-three-quarter", "face-profile", "face-smile", "body-front",
    "body-profile", "body-rear", "walk", "jog", "seated", "talk", "explore", "six-rigs",
)


def metrics(page):
    return page.evaluate("JSON.parse(window.characterLabMetrics)")


def until(page, predicate, description, seconds=25):
    deadline = monotonic() + seconds
    while monotonic() < deadline:
        if predicate():
            return
        page.wait_for_timeout(200)
    raise AssertionError(f"{description}: {metrics(page)}")


def tap(page, name):
    x, y = metrics(page)["controls"][name]
    page.touchscreen.tap(x * page.viewport_size["width"], y * page.viewport_size["height"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("build", type=Path)
    parser.add_argument("captures", type=Path)
    parser.add_argument("--chromium")
    args = parser.parse_args()
    args.captures.mkdir(parents=True, exist_ok=True)

    handler = partial(SimpleHTTPRequestHandler, directory=args.build.resolve())
    with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://{server.server_address[0]}:{server.server_port}/?review"
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.chromium, args=[
                "--no-sandbox", "--enable-webgl", "--use-gl=angle", "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
            ])
            page = browser.new_page(viewport={"width": 1120, "height": 700}, has_touch=True)
            failures = []
            page.on("pageerror", lambda error: failures.append(str(error)))
            page.on("console", lambda msg: failures.append(msg.text) if msg.type == "error" else None)
            now = monotonic()
            page.goto(url, wait_until="domcontentloaded")
            deadline = monotonic() + 45
            while not page.evaluate("Boolean(window.characterLabMetrics) && typeof window.characterLabReview === 'function'"):
                if monotonic() >= deadline:
                    raise RuntimeError(f"Godot lab did not report readiness. Browser errors: {failures}")
                page.wait_for_timeout(200)
            startup = round(monotonic() - now, 2)
            for name in VIEWS:
                page.evaluate("(name) => window.characterLabReview(name)", name)
                page.wait_for_timeout(420)
                page.screenshot(path=args.captures / f"{name}.png", timeout=20000)
            page.set_viewport_size({"width": 956, "height": 440})
            page.evaluate("window.characterLabReview('resume')")
            until(page, lambda: metrics(page)["rigs"] == 1, "Review mode did not restore one rig")

            shots = []
            for target in (1, 6, 18):
                if target != 1:
                    tap(page, "Rig count")
                    until(page, lambda: metrics(page)["rigs"] == target, f"Touch did not select {target} rigs")
                samples = []
                for _ in range(6):
                    page.wait_for_timeout(470)
                    sample = metrics(page)
                    assert sample["rigs"] == target, sample
                    samples.append(sample)
                shots.append({
                    "rigs": target,
                    "median_fps": median(s["fps"] for s in samples),
                    "median_draws": median(s["draws"] for s in samples),
                    "median_primitives": median(s["primitives"] for s in samples),
                    "fps_samples": [s["fps"] for s in samples],
                })
                page.screenshot(path=args.captures / f"landscape-{target:02d}.png")

            tap(page, "Rig count")
            until(page, lambda: metrics(page)["rigs"] == 1, "Touch did not restore one rig")
            tap(page, "Explore")
            until(page, lambda: metrics(page)["view"] == "Explore", "Touch did not enter Explore")
            page.screenshot(path=args.captures / "landscape-explore.png")
            cdp = page.context.new_cdp_session(page)
            cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [
                {"x": 150, "y": 360, "id": 1}, {"x": 780, "y": 335, "id": 2},
            ]})
            cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [
                {"x": 150, "y": 301, "id": 1}, {"x": 742, "y": 335, "id": 2},
            ]})
            until(page, lambda: abs(metrics(page)["z"]) > 0.25 and metrics(page)["clip"] == "Walk",
                  "The held touch stick did not start a walk", seconds=8)
            moved = metrics(page)
            cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            assert abs(moved["z"]) > 0.25 and abs(moved["yaw"] - 3.14159) > 0.06, moved
            assert moved["clip"] == "Walk", moved
            until(page, lambda: metrics(page)["clip"] == "Idle", "Touch release did not restore idle")
            assert not failures, failures
            report = {
                "browser": browser.version,
                "device": "Linux desktop, software WebGL 2, 956×440 CSS px, DPR 1",
                "startup_local_http_s": startup,
                "samples": shots,
                "simultaneous_touch_move_orbit": "passed",
                "startup_and_runtime_errors": failures,
            }
            (args.captures / "browser-metrics.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
