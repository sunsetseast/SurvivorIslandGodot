"""Exercise real game UI and sync against a local Supabase stack in isolated browser contexts."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from threading import Thread
from time import monotonic
from uuid import uuid4

from playwright.sync_api import sync_playwright

from integration import Backend

PRODUCTION = "https://hjmhgibfbxgzqvfdomoj.supabase.co"
VIEWPORT = {"width": 956, "height": 440}
BROWSER_FLAGS = ["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]


def review(page, condition):
    return page.wait_for_function(
        f"window.survivorApp && ((app) => {condition})(JSON.parse(window.survivorApp))"
    )


def button(page, name):
    data = review(page, f'app.actions["{name}"]').json_value()
    page.touchscreen.tap(data[0] * VIEWPORT["width"], data[1] * VIEWPORT["height"])


def field(page, name, text):
    button(page, name)
    page.wait_for_function("document.activeElement instanceof HTMLInputElement")
    assert page.evaluate("document.activeElement.type") == ("password" if name == "password" else "text")
    page.keyboard.type(text)
    page.wait_for_function("(length) => document.activeElement.value.length === length", arg=len(text))
    page.keyboard.press("Enter")


def login(page, email, password):
    button(page, "account")
    button(page, "sign_in")
    field(page, "email", email)
    field(page, "password", password)
    button(page, "submit")
    review(page, 'app.actions.cloud_list')


def local_snapshot(page, account):
    entries = page.evaluate(
        """prefix => Object.keys(localStorage)
            .filter(key => key.startsWith(prefix) && /-slot-1-[01]$/.test(key))
            .map(key => JSON.parse(JSON.parse(localStorage.getItem(key)).payload))""",
        "survivor-3b-account-" + account,
    )
    return max(entries, key=lambda value: value["save_revision"])["state"] if entries else None


def remote_snapshot(backend, session):
    rows = backend.rpc("list", session=session)[1]
    if not rows:
        return None
    row = rows[0]
    snapshot = backend.rpc("get", {"id": row["id"]}, session)[1]["snapshot"]
    return row, json.loads(json.loads(snapshot)["payload"])["state"]


def boot(browser, base, backend, strategy):
    context = browser.new_context(viewport=VIEWPORT, has_touch=True)

    def relay(route):
        path = route.request.url.removeprefix(PRODUCTION)
        if strategy["offline"] and path.startswith("/rest/v1/"):
            route.abort()
        else:
            response = route.fetch(url=backend.url + path, max_redirects=0, headers={**route.request.headers,
                "apikey": backend.key})
            route.fulfill(response=response)

    context.route(PRODUCTION + "/**", relay)
    page = context.new_page()
    page.set_default_timeout(120000)
    page.on("pageerror", lambda error: print("Browser runtime error:", str(error).splitlines()[0]))
    start = monotonic()
    page.goto(base, wait_until="domcontentloaded")
    review(page, 'app.screen === "MAIN"')
    return context, page, round((monotonic() - start) * 1000)


def run(backend, directory, chromium):
    suffix = uuid4().hex
    email_a, email_b = [f"browser-{label}-{suffix}@example.test" for label in ("a", "b")]
    password = "Browser-Temp!" + suffix
    token_a = backend.register(email_a, password)
    token_b = backend.register(email_b, password)
    account = token_a["user"]["id"]
    strategy = {"offline": False}
    with ThreadingHTTPServer(("127.0.0.1", 0), partial(SimpleHTTPRequestHandler, directory=directory)) as server,             sync_playwright() as playwright:
        Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}/?review"
        browser = playwright.chromium.launch(executable_path=chromium, args=BROWSER_FLAGS)
        first, a1, cold = boot(browser, url, backend, strategy)
        button(a1, "new")
        button(a1, "slot1")
        review(a1, 'app.screen === "SESSION"')
        button(a1, "menu")
        review(a1, 'app.screen === "MAIN"')
        login(a1, email_a, password)
        button(a1, "guest_import")
        button(a1, "guest1")
        button(a1, "destination1")
        review(a1, "app.actions.cloud_list")
        start = monotonic()
        cloud = None
        while monotonic() - start < 30:
            a1.wait_for_timeout(350)
            cloud = remote_snapshot(backend, token_a)
            if cloud:
                break
        assert cloud and cloud[1] == local_snapshot(a1, account), "Guest import changed the snapshot"
        import_ms = round((monotonic() - start) * 1000)
        assert a1.evaluate("Object.keys(localStorage).some(k=>k.startsWith('survivor-3a-slot-1-'))")

        second, a2, second_start = boot(browser, url, backend, strategy)
        assert local_snapshot(a2, account) is None, "Browser contexts share account storage"
        login(a2, email_a, password)
        button(a2, "cloud_list")
        button(a2, "cloud1")
        button(a2, "restore")
        button(a2, "destination1")
        review(a2, 'app.screen === "MAIN"')
        assert local_snapshot(a2, account) == cloud[1], "Cross-device checkpoint changed"
        button(a2, "continue")
        review(a2, 'app.screen === "SESSION"')

        strategy["offline"] = True
        button(a2, "save")
        previous = cloud[0]["revision"]
        assert remote_snapshot(backend, token_a)[0]["revision"] == previous
        local = local_snapshot(a2, account)
        assert local["revision"] > cloud[1]["revision"]
        a2.wait_for_timeout(600)
        strategy["offline"] = False
        started = monotonic()
        while monotonic() - started < 45:
            a2.wait_for_timeout(300)
            cloud = remote_snapshot(backend, token_a)
            if cloud[0]["revision"] > previous:
                break
        assert cloud[0]["revision"] > previous and cloud[1] == local, "Offline checkpoint did not synchronize"
        reconnect_ms = round((monotonic() - started) * 1000)

        button(a1, "back")
        button(a1, "account")
        button(a1, "sign_out")
        review(a1, "app.actions.sign_in")
        button(a1, "back")
        login(a1, email_b, password)
        button(a1, "back")
        button(a1, "load")
        review(a1, 'app.screen === "SLOTS"')
        assert not a1.evaluate("Object.keys(localStorage).some(k=>k.startsWith('survivor-3b-account-' + "
                               + json.dumps(token_b["user"]["id"]) + " + '-slot-'))")
        assert backend.rpc("list", session=token_b)[1] == []
        assert backend.rpc("get", {"id": cloud[0]["id"]}, token_b)[1]["status"] == "missing"
        # Diagnostics must never expose private auth state.
        review_data = a1.evaluate("JSON.parse(window.survivorApp)")
        assert set(review_data) == {"screen", "actions"}
        first.close()
        second.close()
        browser.close()
    for token in (token_a, token_b):
        assert backend.request("/functions/v1/delete-player", {"password": password}, token)[0] == 200
    print(f"Guest import, independent storage restoration, offline resync, and account switching passed. "
          f"Cold starts {cold:,} and {second_start:,} ms, import poll {import_ms:,} ms, "
          f"reconnect including backoff {reconnect_ms:,} ms.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--chromium")
    args = parser.parse_args()
    run(Backend("http://127.0.0.1:54321", os.environ["SURVIVOR_TEST_PUBLIC_KEY"],
                "http://127.0.0.1:54324"), str(args.build.resolve()), args.chromium)
