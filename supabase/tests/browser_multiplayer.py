"""Two independently signed-in Chromium contexts through the playable Web export."""
import argparse
from contextlib import ExitStack
import json
import os
from pathlib import Path
import secrets
import socket
import statistics
import subprocess
import tempfile
from time import sleep

from playwright.sync_api import sync_playwright

from browser_sync import BROWSER_FLAGS, boot, button, field, login, review
from integration import Backend
from multiplayer import provision, sql


def start(scope, command, output, env=None):
    log = scope.enter_context(output.open("wb"))
    process = subprocess.Popen(command, env=env, stdout=log, stderr=log)

    def stop():
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=8)

    scope.callback(stop)
    return process


def ready(process, port):
    for _ in range(150):
        assert process.poll() is None, "Local service exited"
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return
        except OSError:
            sleep(.1)
    raise AssertionError("Local service did not listen")


def capture(page):
    state = {}

    def received(raw):
        if isinstance(raw, str):
            item = json.loads(raw)
            state[item["type"]] = item

    page.on("websocket", lambda sock: sock.on("framereceived", received))
    return state


def wait_browser(page, predicate):
    for _ in range(100):
        if predicate():
            return
        page.wait_for_timeout(100)
    raise AssertionError("Browser did not receive expected server state")


def camp_metrics(page):
    return page.wait_for_function("window.tonsaiMetrics").evaluate("metrics => JSON.parse(metrics)")


def frame_times(page, seconds=2):
    samples = page.evaluate("""seconds => new Promise(resolve => {
        const samples = [];
        const deadline = setTimeout(() => resolve(samples), (seconds + 8) * 1000);
        let first, previous;
        const frame = (time) => {
            if (first === undefined) first = time;
            if (previous !== undefined) samples.push(time - previous);
            previous = time;
            if (time - first >= seconds * 1000) {
                clearTimeout(deadline);
                resolve(samples);
            } else requestAnimationFrame(frame);
        };
        requestAnimationFrame(frame);
    })""", seconds)
    if len(samples) < 2:
        fps = camp_metrics(page)["fps"]
        return {"mean_ms_from_engine_fps": round(1000 / fps, 1)} if fps > 0 else {}
    return (round(statistics.median(samples), 1), round(sorted(samples)[int(.95 * (len(samples) - 1))], 1))


def touch_walk(context, page):
    x, y = camp_metrics(page)["controls"]["stick"]
    cdp = context.new_cdp_session(page)
    viewport = page.viewport_size
    point = {"x": x * viewport["width"], "y": y * viewport["height"], "id": 1}
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [point]})
    point["y"] -= 50
    cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [point]})
    page.wait_for_timeout(1300)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})


def run(args, backend, dsn):
    key = secrets.token_hex(32)
    assert sql(dsn, "select count(*) from survivor_multiplayer.recovery;") == "0", "Use a fresh local fixture"
    sql(dsn, "insert into survivor_multiplayer.recovery (secret_hash) values (sha256(convert_to(:'key', 'UTF8')));",
        [f"key={key}"])
    suffix = secrets.token_hex(6)
    password = "Browser-3C!" + suffix
    accounts = []
    try:
        accounts = provision(backend, suffix, password)
        with ExitStack() as scope:
            temporary = Path(scope.enter_context(tempfile.TemporaryDirectory(prefix="survivor-browser-")))
            env = {**os.environ, "SURVIVOR_WS_PORT": str(args.ws_port), "SURVIVOR_CHECKPOINT_KEY": key,
                   "SURVIVOR_LOCAL_SUPABASE": backend.url}
            server = start(scope, [args.godot, "--headless", "--path", str(args.stage), "--script", "res://server/main.gd"],
                           args.stage.parent / "browser-multiplayer-server.log", env)
            ready(server, args.ws_port)
            caddy = temporary / "Caddyfile"
            caddy.write_text(f"""{{
    admin off
    auto_https off
}}
http://127.0.0.1:{args.web_port} {{
    handle /ws {{
        reverse_proxy 127.0.0.1:{args.ws_port}
    }}
    handle {{
        root * {json.dumps(str(args.build.resolve()))}
        file_server
    }}
}}
""")
            gateway = start(scope, [args.caddy, "run", "--config", str(caddy), "--adapter", "caddyfile"],
                            args.stage.parent / "browser-multiplayer-gateway.log")
            ready(gateway, args.web_port)
            chromium = scope.enter_context(sync_playwright()).chromium
            flags = [*BROWSER_FLAGS, "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                     "--disable-backgrounding-occluded-windows"]
            browser = chromium.launch(executable_path=args.chromium, args=flags)
            other_browser = chromium.launch(executable_path=args.chromium, args=flags)
            location = f"http://127.0.0.1:{args.web_port}/?review"
            strategy = {"offline": False}
            viewport = {"width": 756, "height": 348}
            first, a, _ = boot(browser, location, backend, strategy, viewport=viewport)
            a.set_default_timeout(45_000)
            seen_a = capture(a)
            print("Client A booted")
            button(a, "new")
            button(a, "slot1")
            review(a, 'app.screen === "SESSION"')
            camp_metrics(a)
            baseline = frame_times(a)
            print("Offline baseline sampled")
            button(a, "menu")
            login(a, accounts[0][0], password)
            button(a, "back")
            button(a, "multiplayer")
            review(a, 'app.connected === true')
            button(a, "create")
            wait_browser(a, lambda: "room" in seen_a)
            print("Client A created a room")
            second, b, _ = boot(other_browser, location, backend, strategy, viewport=viewport)
            b.set_default_timeout(45_000)
            seen_b = capture(b)
            login(b, accounts[1][0], password)
            button(b, "back")
            button(b, "multiplayer")
            review(b, 'app.connected === true')
            field(b, "join_code", seen_a["room"]["code"])
            button(b, "join")
            review(a, "app.host_ready === true")
            button(a, "start")
            print("Both authenticated clients joined")
            for page in (a, b):
                review(page, 'app.screen === "SESSION" && app.active && !app.actions.save')
                camp_metrics(page)
            print("Both rendered Tonsai")
            for index, (page, other, seen, identity) in enumerate(
                ((a, b, seen_b, "explorer"), (b, a, seen_a, "jeremy"))
            ):
                start_pose = seen["state"]["movement"][identity][:3]
                visual_start = camp_metrics(other)["remote_peer"]
                assert len(visual_start) == 3
                context = first if index == 0 else second
                touch_walk(context, page)
                wait_browser(other, lambda: sum((x - y) ** 2 for x, y in zip(
                    start_pose, seen["state"]["movement"][identity][:3])) > .16)
                other.wait_for_function("""start => JSON.parse(window.tonsaiMetrics).remote_peer
                    .reduce((sum, value, i) => sum + (value - start[i]) ** 2, 0) > .16""", arg=visual_start)
                print(f"Touch movement {index + 1} rendered on peer")
            a.bring_to_front()
            multiplayer = frame_times(a)
            button(b, "menu")
            review(b, 'app.screen === "MAIN"')
            button(b, "multiplayer")
            print("Client B reopened multiplayer")
            review(b, 'app.screen === "SESSION" && app.active')
            assert seen_b["room"]["controlled"] == "jeremy"
            first.close()
            second.close()
            browser.close()
            other_browser.close()
            print("PASS: independent touch clients, replicated movement both ways, same contestant after leaving")
            print(f"Chromium SwiftShader frame time median/p95, ms — offline {baseline}, two clients {multiplayer}")
    finally:
        sql(dsn, "delete from survivor_multiplayer.recovery where secret_hash = sha256(convert_to(:'key', 'UTF8'));",
            [f"key={key}"])
        for _, session in accounts:
            sql(dsn, "delete from auth.users where id = :'account'::uuid;", [f"account={session['user']['id']}"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, default=Path("build/server"))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--caddy", default="caddy")
    parser.add_argument("--chromium")
    parser.add_argument("--web-port", type=int, default=8060)
    parser.add_argument("--ws-port", type=int, default=8061)
    settings = parser.parse_args()
    backend = Backend("http://127.0.0.1:54321", os.environ["SURVIVOR_TEST_PUBLIC_KEY"], "http://127.0.0.1:54324")
    dsn = os.environ.get("SURVIVOR_TEST_DB_DSN", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
    from urllib.parse import urlparse
    assert urlparse(dsn).hostname in ("127.0.0.1", "localhost"), "Tests require a disposable local database"
    run(settings, backend, dsn)
