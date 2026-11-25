"""Two independent clients, an actual Godot server, and disposable loopback Supabase services."""
import argparse
import asyncio
import base64
from collections import deque
import hmac
import json
from math import dist, hypot, sin
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
from time import monotonic, time
from urllib.parse import urlparse

from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

from integration import Backend


def signed_claims(secret, claims):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=")
    body = encode({"alg": "HS256", "typ": "JWT"}) + b"." + encode(claims)
    signature = base64.urlsafe_b64encode(hmac.digest(secret.encode(), body, "sha256")).rstrip(b"=")
    return (body + b"." + signature).decode()


def provision(backend, suffix, password):
    admin = os.environ.get("SURVIVOR_TEST_SERVICE_ROLE")
    sessions = []
    for label in ("a", "b"):
        email = f"phase3c-{label}-{suffix}@example.test"
        if admin:
            status, _ = backend.auth("admin/users", {"email": email, "password": password, "email_confirm": True},
                                     {"access_token": admin})
            assert status in (200, 201), f"Local admin account creation failed ({status})"
            session = backend.login(email, password)
        else:
            session = backend.register(email, password)
        sessions.append((email, session))
    return sessions


def sql(dsn, statement, variables=()):
    options = [item for variable in variables for item in ("-v", variable)]
    return subprocess.run([os.environ.get("SURVIVOR_PSQL", "psql"), dsn, "-XqAt", "-v", "ON_ERROR_STOP=1", *options],
                          input=statement, text=True, capture_output=True, check=True).stdout.strip()


class Client:
    def __init__(self, url):
        self.url = url
        self.delay = 0
        self.serial = 0
        self.command_sequence = 1
        self.messages = deque(maxlen=100)
        self.state = {}
        self.room = {}
        self.camp = {}
        self.journal = []
        self.bytes = 0
        self.packets = 0
        self.delivery_at = 0.0

    async def open(self):
        self.socket = await connect(self.url, max_size=65536, ping_interval=None)
        self.task = asyncio.create_task(self._receive())
        self.heartbeat = asyncio.create_task(self._keep_connected())
        return self

    async def _receive(self):
        try:
            async for raw in self.socket:
                if self.delay:
                    loop = asyncio.get_running_loop()
                    half_rtt = (self.delay + 8 * sin(self.packets)) / 2000
                    self.delivery_at = max(self.delivery_at + .0001, loop.time() + half_rtt)
                    loop.call_at(self.delivery_at, self._deliver, raw)
                else:
                    self._deliver(raw)
        except ConnectionClosed:
            pass

    def _deliver(self, raw):
        self.packets += 1
        self.bytes += len(raw.encode())
        note = json.loads(raw)
        if note["type"] == "camp":
            self.camp = {"cast": note["cast"], "objects": note["objects"]}
        elif note["type"] == "state":
            if not self.state:
                asyncio.create_task(self.send("ready"))
            note["view"].update(self.camp)
            self.state = note
        elif note["type"] == "room":
            self.room = note
        elif note["type"] == "journal_reset":
            self.journal.clear()
        elif note["type"] == "journal":
            self.journal.extend(note["records"])
        self.messages.append(note)

    async def _keep_connected(self):
        try:
            while True:
                await asyncio.sleep(2)
                await self.send("ping")
        except ConnectionClosed:
            pass

    async def send(self, message_type, **fields):
        if self.delay:
            await asyncio.sleep((self.delay + 8 * sin(self.serial)) / 2000)
        await self.socket.send(json.dumps({"v": 1, "type": message_type, **fields}))

    async def wait(self, kind, accept=lambda _: True, timeout=8):
        finish = monotonic() + timeout
        while monotonic() < finish:
            for message in self.messages:
                if message["type"] == kind and accept(message):
                    self.messages.remove(message)
                    return message
            await asyncio.sleep(.02)
        raise AssertionError(f"Timed out waiting for {kind}")

    async def auth(self, token):
        await self.send("auth", token=token)
        await self.wait("authorized", timeout=12)
        return self

    async def move(self, x, z, run=False):
        self.serial += 1
        await self.send("move", seq=self.serial, x=x, z=z, run=run, dive=False, vertical=0.0)

    async def talk(self, kind, target, topic="", command_id=None, seq=None):
        command = {"id": command_id or secrets.token_hex(16), "seq": seq or max(self.command_sequence, self.state["next_command"]),
                   "kind": "talk." + kind, "target": target, "topic": topic}
        await self.send("talk", **command)
        receipt = await self.wait("receipt", lambda msg: msg["result"]["id"] == command["id"])
        if receipt["result"]["ok"] and kind == "respond":
            self.command_sequence = max(self.command_sequence, command["seq"] + 1)
        return command, receipt["result"]

    async def close(self):
        self.heartbeat.cancel()
        await self.socket.close()
        await self.task


async def reject(url, raw, token=None):
    client = await Client(url).open()
    try:
        if token:
            await client.auth(token)
        await client.socket.send(raw)
        await asyncio.wait_for(client.socket.wait_closed(), 5)
    finally:
        await client.close()


async def approach(client):
    target = "cirie"
    for _ in range(220):
        poses = client.state["movement"]
        x, _, z = poses[client.room["controlled"]][:3]
        options = [(hypot(p[0] - x, p[2] - z), name, p) for name, p in poses.items()
                   if name not in ("explorer", "jeremy")]
        gap, target, p = min(options)
        if gap < 1.8:
            await client.move(0, 0)
            await asyncio.sleep(.2)
            command, receipt = await client.talk("begin", target)
            if receipt["ok"]:
                return target
        if gap > .1:
            await client.move((p[0] - x) / gap * .94, (p[2] - z) / gap * .94, True)
        await asyncio.sleep(.055)
    raise AssertionError(f"Could not reach NPC {target}")


async def run(settings):
    backend = Backend("http://127.0.0.1:54321", os.environ["SURVIVOR_TEST_PUBLIC_KEY"], "http://127.0.0.1:54324")
    dsn = os.environ.get("SURVIVOR_TEST_DB_DSN", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
    assert urlparse(dsn).hostname in ("127.0.0.1", "localhost"), "Tests require a disposable local database"
    key = secrets.token_hex(32)
    existing = sql(dsn, "select count(*) from survivor_multiplayer.recovery;")
    assert existing == "0", "Use a fresh local database. Existing checkpoint preserved."
    sql(dsn, """insert into survivor_multiplayer.recovery (secret_hash)
                  values (sha256(convert_to(:'key', 'UTF8')));""", [f"key={key}"])
    accounts = []
    processes = []
    clients = []
    with tempfile.TemporaryDirectory(prefix="survivor-3c-") as temporary:
        signal_file = Path(temporary) / "shutdown"
        env = {**os.environ, "SURVIVOR_CHECKPOINT_KEY": key, "SURVIVOR_LOCAL_SUPABASE": backend.url,
               "SURVIVOR_WS_PORT": str(settings.port), "SURVIVOR_SHUTDOWN_FILE": str(signal_file)}
        url = f"ws://127.0.0.1:{settings.port}"

        async def fresh():
            stream = open(settings.log, "ab")
            with stream:
                process = subprocess.Popen([settings.godot, "--headless", "--path", str(settings.stage),
                                            "--script", "res://server/main.gd"], env=env, stdout=stream, stderr=stream)
            processes.append(process)
            for _ in range(100):
                assert process.poll() is None, "Dedicated process exited; inspect the server log"
                try:
                    pending = await Client(url).open()
                    await pending.close()
                    return process
                except OSError:
                    await asyncio.sleep(.1)
            raise AssertionError("Dedicated process did not listen")

        async def open_client(token):
            client = await Client(url).open()
            clients.append(client)
            return await client.auth(token)

        try:
            suffix = secrets.token_hex(6)
            accounts = provision(backend, suffix, "Temp-3C!" + suffix)
            token_a, token_b = [session["access_token"] for _, session in accounts]
            assert token_a != token_b
            process = await fresh()
            bad = token_a.rsplit(".", 1)
            forged = bad[0] + "." + ("a" if bad[1][0] != "a" else "b") + bad[1][1:]
            await reject(url, json.dumps({"v": 1, "type": "auth", "token": forged}))
            await reject(url, json.dumps({"v": 1, "type": "auth", "token": token_a, "account": "forged"}))
            await reject(url, "{bad json")
            await reject(url, "x" * 4097)
            part = token_a.split(".")[1]
            claims = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
            wrong_project = signed_claims(secrets.token_hex(32), {**claims, "iss": "https://example.test/auth/v1"})
            await reject(url, json.dumps({"v": 1, "type": "auth", "token": wrong_project}))
            if os.environ.get("SURVIVOR_TEST_JWT_SECRET"):
                secret = os.environ["SURVIVOR_TEST_JWT_SECRET"]
                expired = signed_claims(secret, {**claims, "exp": int(time()) - 300})
                await reject(url, json.dumps({"v": 1, "type": "auth", "token": expired}))
            a, b = await open_client(token_a), await open_client(token_b)
            await a.send("create")
            room = await a.wait("room")
            await b.send("join", code=room["code"])
            await b.wait("room")
            await a.wait("room", lambda m: len(m["roster"]) == 2)
            await a.send("start")
            start_a, start_b = await asyncio.gather(a.wait("state"), b.wait("state"))
            assert a.room["controlled"] == "explorer" and b.room["controlled"] == "jeremy"
            assert len(start_a["movement"]) == 6 and start_a["view"]["tick"] == start_b["view"]["tick"]
            assert not start_a["active"] and not start_b["active"]
            await asyncio.gather(a.wait("state", lambda m: m["active"]), b.wait("state", lambda m: m["active"]))
            roster = sql(dsn, """select count(*) from survivor_multiplayer.recovery,
                jsonb_each(payload->'season'->'roster');""")
            assert roster == "18"
            checkpoint = "/rest/v1/rpc/phase3c_checkpoint"
            assert backend.request(checkpoint, {"secret": key, "expected": -1, "payload": None}, accounts[0][1])[0] >= 400
            assert backend.request(checkpoint, {"secret": "0" * 64, "expected": 0, "payload": {}})[0] >= 400
            _, out_of_range = await a.talk("begin", "parvati")
            assert not out_of_range["ok"]
            target = "cirie"
            _, opened = await a.talk("begin", target)
            if not opened["ok"]:
                target = await approach(a)
            command, receipt = await a.talk("respond", target, "camp")
            assert receipt["ok"] and receipt["event"]["reply"]
            _, duplicate = await a.talk("respond", target, "camp", command["id"], command["seq"])
            assert duplicate == receipt
            assert [row["id"] for row in a.journal] == [command["id"]]
            assert not b.journal and all("journal" not in row for row in b.state["view"]["cast"].values())
            checkpoint_tick = a.state["view"]["tick"]
            _, closed = await a.talk("end", target)
            assert closed["ok"]
            measurements = []
            for delay, client, observer in ((50, a, b), (100, b, a), (200, a, b)):
                initial = observer.state["movement"][client.room["controlled"]][:3]
                tick = client.state["view"]["tick"]
                position = initial
                direction = 1 if delay != 100 else -1
                client.delay = observer.delay = delay
                client.messages = deque((msg for msg in client.messages if msg["type"] != "pong"), maxlen=100)
                stamp = monotonic()
                await client.send("ping")
                await client.wait("pong")
                rtt = (monotonic() - stamp) * 1000
                started = monotonic()
                pending = []
                for _ in range(32):
                    pending.append(asyncio.create_task(client.move(0, direction, True)))
                    await asyncio.sleep(.055)
                    position = observer.state["movement"][client.room["controlled"]][:3]
                    if dist(initial, position) > .6:
                        break
                observed_ms = round((monotonic() - started) * 1000)
                await asyncio.gather(*pending)
                await client.move(0, 0)
                client.delay = observer.delay = 0
                assert dist(initial, position) > .6 and client.state["view"]["tick"] > tick
                measurements.append((delay, round(rtt), observed_ms))
                await asyncio.sleep(.25)
            assert any(dist(start_a["movement"][id][:3], a.state["movement"][id][:3]) > .3
                       for id in ("cirie", "yul", "parvati", "kelley"))
            for payload in [
                {"type": "move", "seq": 50, "x": 4, "z": 0, "run": False, "dive": False, "vertical": 0},
                {"type": "move", "seq": 50, "x": 0, "z": 0, "run": False, "dive": False, "vertical": 0,
                 "position": [10, 0, 10]},
                {"type": "talk", "seq": 1, "id": secrets.token_hex(16), "kind": "talk.begin",
                 "target": "cirie", "topic": "", "actor": "explorer"},
                {"type": "arrival", "target": "cirie"}, {"type": "journal", "actor": "explorer"},
            ]:
                await reject(url, json.dumps({"v": 1, **payload}), token_b)
            b = await open_client(token_b)
            await b.wait("state", lambda m: m["active"])
            # Drop the earlier loading snapshot before measuring this disconnection.
            b.messages = deque((msg for msg in b.messages if msg["type"] != "state"), maxlen=100)
            await a.close()
            pause = await b.wait("state", lambda m: not m["active"], timeout=8)
            assert pause["view"]["tick"] >= checkpoint_tick
            paused_tick = pause["view"]["tick"]
            await asyncio.sleep(.4)
            assert b.state["view"]["tick"] == paused_tick
            a = await open_client(token_a)
            await a.wait("state", lambda m: m["active"])
            assert a.room["controlled"] == "explorer"
            assert [row["id"] for row in a.journal] == [command["id"]]
            old_b = b
            b = await open_client(token_b)
            await old_b.wait("fatal", lambda m: m["reason"] == "connection_replaced")
            await asyncio.wait_for(old_b.socket.wait_closed(), 4)
            await b.wait("state", lambda m: m["active"])
            await a.close()
            await b.close()
            await asyncio.sleep(.6)
            proc_stat = Path(f"/proc/{process.pid}/status").read_text()
            rss = next(line for line in proc_stat.splitlines() if line.startswith("VmRSS:"))
            process.kill()
            process.wait(10)
            process = await fresh()
            a, b = await open_client(token_a), await open_client(token_b)
            await asyncio.gather(a.wait("state", lambda m: m["active"]), b.wait("state", lambda m: m["active"]))
            assert a.state["view"]["tick"] >= checkpoint_tick
            assert [row["id"] for row in a.journal] == [command["id"]] and not b.journal
            await a.talk("respond", target, "camp", command["id"], command["seq"])
            assert len(a.journal) == 1
            began = monotonic()
            count, size = a.packets, a.bytes
            def cpu_ticks():
                values = Path(f"/proc/{process.pid}/stat").read_text().split(") ", 1)[1].split()
                return int(values[11]) + int(values[12])
            first_cpu = cpu_ticks()
            await asyncio.sleep(10)
            seconds = monotonic() - began
            cores = (cpu_ticks() - first_cpu) / os.sysconf("SC_CLK_TCK") / seconds
            print(f"Players=2; roster=18; Tonsai=6; {rss}; cores={cores:.3f}; messages/client/s={(a.packets-count)/seconds:.2f}; "
                  f"payload bytes/client/s={(a.bytes-size)/seconds:.0f}")
            print("Latency samples (nominal RTT, ping RTT, movement observed ms):", measurements)
            status, renewed = backend.auth("token?grant_type=refresh_token",
                                           {"refresh_token": accounts[0][1]["refresh_token"]})
            assert status == 200
            await a.send("renew", token=renewed["access_token"])
            await a.wait("authorized")
            assert a.room["controlled"] == "explorer"
            status, _ = backend.auth("logout?scope=local", {}, accounts[1][1])
            assert status in (200, 204)
            started = monotonic()
            await b.wait("fatal", lambda m: m["reason"] == "authorization_lost", timeout=58)
            print(f"Live revocation detected after {monotonic() - started:.1f}s")
            await reject(url, json.dumps({"v": 1, "type": "auth", "token": token_b}))
            if os.environ.get("SURVIVOR_TEST_JWT_SECRET"):
                short = signed_claims(os.environ["SURVIVOR_TEST_JWT_SECRET"],
                                      {**claims, "exp": int(time()) + 4})
                expiring = await open_client(short)
                await asyncio.wait_for(expiring.socket.wait_closed(), 6)
            signal_file.touch()
            assert process.wait(timeout=12) == 0, "Graceful server shutdown failed"
            print("PASS: ownership, authority, movement, private conversation, durable duplicate, suspension, restart")
        finally:
            for client in clients:
                await client.close()
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=8)
            if not settings.keep_fixture:
                sql(dsn, "delete from survivor_multiplayer.recovery where secret_hash = sha256(convert_to(:'key', 'UTF8'));",
                    [f"key={key}"])
                for _, session in accounts:
                    sql(dsn, "delete from auth.users where id = :'account'::uuid;",
                        [f"account={session['user']['id']}"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--stage", type=Path, default=Path("build/server"))
    parser.add_argument("--log", type=Path, default=Path("build/server-integration.log"))
    parser.add_argument("--port", type=int, default=8061)
    parser.add_argument("--keep-fixture", action="store_true")
    asyncio.run(run(parser.parse_args()))
