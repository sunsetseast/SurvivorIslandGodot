"""Optional developer-build benchmark/clipboard regression; software GPU only."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
from threading import Thread
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("build", type=Path)
parser.add_argument("captures", type=Path)
args = parser.parse_args()
args.captures.mkdir(parents=True, exist_ok=True)
handler = partial(SimpleHTTPRequestHandler, directory=args.build.resolve())
with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server, sync_playwright() as playwright:
    Thread(target=server.serve_forever, daemon=True).start()
    browser = playwright.chromium.launch(args=[
        "--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader",
        "--enable-unsafe-swiftshader",
    ])
    context = browser.new_context(
        viewport={"width": 956, "height": 440}, has_touch=True,
        permissions=["clipboard-read", "clipboard-write"],
    )
    page = context.new_page()
    errors = []
    requests = []
    page.on("request", lambda request: requests.append(request.url))
    page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(f"http://127.0.0.1:{server.server_port}/?benchmark", wait_until="networkidle")
    page.wait_for_timeout(4000)
    page.screenshot(path=args.captures / "ready.png")
    # Fixed 956x440 fixture, matching the inspected CSS-scaled benchmark layout.
    page.mouse.click(298, 29)  # Start, default six rigs / isolated / Full.
    page.wait_for_timeout(27000)
    page.screenshot(path=args.captures / "complete.png")
    page.mouse.click(330, 258)  # Copy Report opens a native trusted-tap dialog.
    dialog = page.get_by_role("dialog", name="Benchmark report", exact=True)
    dialog.wait_for(state="visible")
    dialog.get_by_role("button", name="Copy", exact=True).click()
    dialog.get_by_text("Report copied", exact=True).wait_for(state="visible")
    report = json.loads(page.evaluate("navigator.clipboard.readText()"))
    assert report["visible_rigs"] == 6 and report["simulated_contestants"] == 18, report
    assert report["warmup_seconds"] == 3 and 20 <= report["sampling_seconds"] < 30, report
    assert report["average_fps"] > 0 and report["median_ms"] > 0 and report["p95_ms"] >= report["median_ms"]
    for field in ("static_memory_bytes", "render_total_memory_estimate_bytes"):
        assert isinstance(report[field], str) or report[field] > 0, (field, report[field])
    assert not ({"account", "email", "access_token", "refresh_token", "password"} & report.keys())
    dialog.get_by_role("button", name="Close", exact=True).click()
    assert page.get_by_role("dialog", name="Benchmark report").count() == 0
    assert not errors, errors
    assert all(urlparse(url).hostname == "127.0.0.1" for url in requests), requests
    (args.captures / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    browser.close()
