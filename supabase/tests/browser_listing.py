"""Check Cloud Saves from the exact Web export, including mobile scrolling and refresh."""
import argparse
from contextlib import ExitStack
from functools import partial
import gzip
import hashlib
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from threading import Thread
from uuid import uuid4

from playwright.sync_api import sync_playwright

from browser_sync import BROWSER_FLAGS, PRODUCTION, boot, button, field, local_snapshot, login, review
from integration import Backend

PORTRAIT = {"width": 390, "height": 844}
LANDSCAPE = {"width": 932, "height": 430}
KEYBOARD_HEIGHT = 195


class GzipListingGateway(BaseHTTPRequestHandler):
    """A loopback proxy that gives browser Fetch a real compressed list response."""

    protocol_version = "HTTP/1.1"

    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "authorization, apikey, content-type")
        self.send_header("Access-Control-Expose-Headers", "Content-Encoding")

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        headers = {k: self.headers[k] for k in ("Authorization", "Content-Type", "apikey") if k in self.headers}
        connection = HTTPConnection("127.0.0.1", 54321, timeout=15)
        try:
            connection.request("POST", self.path, body, headers)
            response = connection.getresponse()
            data = response.read()
            compressed = (response.status == 200 and self.path == "/rest/v1/rpc/player_data"
                          and json.loads(body).get("action") == "list")
            self.send_response(response.status)
            self.cors()
            self.send_header("Content-Type", response.getheader("Content-Type", "application/json"))
            if compressed:
                self.send_header("Content-Encoding", "gzip")
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                wire = gzip.compress(data)
                self.wfile.write(f"{len(wire):x}\r\n".encode() + wire + b"\r\n0\r\n\r\n")
            else:
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        finally:
            connection.close()


def is_list(response):
    if not response.url.endswith("/rest/v1/rpc/player_data") or response.request.method != "POST":
        return False
    return response.request.post_data_json.get("action") == "list"


def list_from(page, action):
    with page.expect_response(is_list) as pending:
        button(page, action)
    response = pending.value
    assert response.status == 200, "Cloud list HTTP failure"
    data = response.json()
    assert isinstance(data, list), "Unexpected PostgREST list response type"
    return data


def select_from_load(page, email, password):
    button(page, "load")
    button(page, "load_cloud")
    field(page, "email", email)
    field(page, "password", password)
    return list_from(page, "submit")


def upload(backend, session, snapshot, save_id=None, expected=0):
    save_id = save_id or str(uuid4())
    status, data = backend.rpc("put", {
        "id": save_id, "expected": expected, "operation": str(uuid4()), "snapshot": snapshot,
    }, session=session)
    assert status == 200 and data == {"status": "saved", "revision": expected + 1}, "Test upload failed"
    return save_id


def variant(fixture, season):
    entry = json.loads(json.loads(fixture)["payload"])
    entry["state"]["season_id"] = season
    data = json.dumps(entry, separators=(",", ":"))
    return json.dumps({"payload": data, "sha256": hashlib.sha256(data.encode()).hexdigest()})


def touch_scroll(page):
    page.evaluate("""height => {
        Object.defineProperty(visualViewport, 'height', {value: height, configurable: true});
        visualViewport.dispatchEvent(new Event('resize'));
    }""", KEYBOARD_HEIGHT)
    review(page, f"app.actions.cloud3[1] * innerHeight > {KEYBOARD_HEIGHT}")
    cdp = page.context.new_cdp_session(page)
    x = page.viewport_size["width"] / 2
    cdp.send("Input.dispatchTouchEvent", {
        "type": "touchStart", "touchPoints": [{"x": x, "y": 170}],
    })
    for y in (151, 130, 105, 80, 55, 30):
        cdp.send("Input.dispatchTouchEvent", {
            "type": "touchMove", "touchPoints": [{"x": x, "y": y}],
        })
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    review(page, f"app.actions.cloud3 && !app.actions.restore && app.actions.cloud3[1] * innerHeight < {KEYBOARD_HEIGHT}")
    page.evaluate("""() => {
        delete visualViewport.height;
        visualViewport.dispatchEvent(new Event('resize'));
    }""")


def run(backend, session, email, password, build, chromium, fixture):
    http, prior = backend.rpc("list", session=session)
    assert http == 200 and prior == [], "Use an empty, dedicated disposable game account"
    saved = {}
    with ExitStack() as scope:
        server = scope.enter_context(ThreadingHTTPServer(
            ("127.0.0.1", 0), partial(SimpleHTTPRequestHandler, directory=str(build))))
        playwright = scope.enter_context(sync_playwright())
        strategy = {"offline": False}
        if backend.url != PRODUCTION:
            proxy = scope.enter_context(ThreadingHTTPServer(("127.0.0.1", 0), GzipListingGateway))
            Thread(target=proxy.serve_forever, daemon=True).start()
            strategy["wire_url"] = f"http://127.0.0.1:{proxy.server_port}"
        Thread(target=server.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{server.server_port}/?review"
        browser = playwright.chromium.launch(executable_path=chromium, args=BROWSER_FLAGS)
        first, portrait, _ = boot(browser, base, backend, strategy, viewport=PORTRAIT)
        login(portrait, email, password)
        assert list_from(portrait, "cloud_list") == []
        for _ in range(3):
            season = uuid4().hex
            snapshot = variant(fixture, season)
            key = upload(backend, session, snapshot)
            saved[key] = (1, snapshot)
        rows = list_from(portrait, "refresh")
        assert {row["id"] for row in rows} == set(saved)
        review(portrait, "app.actions.cloud1 && app.actions.cloud2 && app.actions.cloud3")
        assert portrait.evaluate("JSON.parse(window.survivorApp).actions.cloud3[1] < 1")
        key = rows[0]["id"]
        snapshot = saved[key][1]
        upload(backend, session, snapshot, key, expected=1)
        saved[key] = (2, snapshot)
        refreshed = list_from(portrait, "refresh")
        assert refreshed[0]["id"] == key and refreshed[0]["revision"] == 2
        button(portrait, "cloud1")
        review(portrait, "app.actions.previous")
        first.close()

        second, landscape, _ = boot(browser, base, backend, strategy, viewport=LANDSCAPE)
        account = session["user"]["id"]
        assert local_snapshot(landscape, account) is None, "Independent browser should start with no local save"
        assert select_from_load(landscape, email, password)[0]["id"] == key
        review(landscape, "app.actions.cloud3")
        touch_scroll(landscape)
        # Refresh resets the list to its top. The shortened viewport check above
        # reached the last row using touch without opening a save by accident.
        landscape.mouse.wheel(0, -500)
        list_from(landscape, "refresh")
        button(landscape, "cloud1")
        button(landscape, "restore")
        button(landscape, "destination1")
        review(landscape, 'app.screen === "SLOTS"')
        assert local_snapshot(landscape, account) == json.loads(json.loads(snapshot)["payload"])["state"]
        second.close()
        browser.close()

    for key, (revision, _) in saved.items():
        status, data = backend.rpc("delete", {"id": key, "expected": revision}, session)
        assert status == 200 and data.get("status") == "deleted", "Disposable test save cleanup failed"
    source = "Hosted PostgREST" if backend.url == PRODUCTION else "Local PostgREST with an exposed gzip header"
    print(f"{source} returned an array. "
          "Three saves appeared in portrait, Refresh picked up revision 2, touch scrolling reached the last row, "
          "and a separate landscape browser restored the checkpoint from Load Game.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--chromium")
    parser.add_argument("--hosted", action="store_true",
                        help="Use an empty verified disposable account supplied in private environment variables")
    args = parser.parse_args()
    if args.hosted:
        backend = Backend(PRODUCTION, os.environ["SURVIVOR_HOSTED_PUBLISHABLE_KEY"], "")
        email = os.environ["SURVIVOR_HOSTED_TEST_EMAIL"]
        password = os.environ["SURVIVOR_HOSTED_TEST_PASSWORD"]
        session = backend.login(email, password)
    else:
        backend = Backend("http://127.0.0.1:54321", os.environ["SURVIVOR_TEST_PUBLIC_KEY"], "http://127.0.0.1:54324")
        email = f"listing-{uuid4().hex}@example.test"
        password = f"Listing-Temp!{uuid4().hex}"
        session = backend.register(email, password)
    run(backend, session, email, password, args.build.resolve(), args.chromium, args.fixture.read_text())
    if not args.hosted:
        backend.request("/functions/v1/delete-player", {"password": password}, session)
