"""Exercise a local Supabase stack with Mailpit and two disposable identities."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
from time import monotonic, sleep
import urllib.error
import urllib.request
from uuid import uuid4


class Backend:
    def __init__(self, url, key, mailpit):
        self.url = url.rstrip("/")
        self.key = key
        self.mailpit = mailpit.rstrip("/")

    def request(self, path, data=None, session=None, method=None, base=None):
        headers = {"apikey": self.key, "Content-Type": "application/json"}
        if session:
            headers["Authorization"] = "Bearer " + session["access_token"]
        body = json.dumps(data).encode() if data is not None else None
        request = urllib.request.Request((base or self.url) + path, body, headers, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            raw = response.read()
            if not raw:
                return response.status, None
            try:
                return response.status, json.loads(raw)
            except json.JSONDecodeError:
                return response.status, None

    def auth(self, path, payload=None, session=None, method=None):
        return self.request("/auth/v1/" + path, payload, session, method)

    def rpc(self, action, args=None, session=None):
        return self.request("/rest/v1/rpc/player_data", {"action": action, "args": args or {}}, session)

    def code(self, address, subject):
        subjects = {subject, {
            "Your Survivor Island verification code": "Confirm Your Email",
            "Your Survivor Island recovery code": "Reset Your Password",
        }[subject]}
        start = monotonic()
        while monotonic() - start < 15:
            status, data = self.request("/api/v1/messages", base=self.mailpit)
            assert status == 200, "Mailpit unavailable"
            for item in data["messages"]:
                if item["Subject"] in subjects and any(to["Address"] == address for to in item["To"]):
                    _, message = self.request("/api/v1/message/" + item["ID"], base=self.mailpit)
                    code = re.search(r"<strong>\s*(\d{6,10})\s*</strong>", message["HTML"])
                    assert code, "Mailpit message did not contain the configured code template"
                    return code[1]
            sleep(.3)
        raise AssertionError("Matching Mailpit message not found")

    def register(self, email, password):
        status, data = self.auth("signup", {"email": email, "password": password})
        assert status in (200, 201) and "access_token" not in data, "Signup issued a session before verification"
        denied, _ = self.auth("token?grant_type=password", {"email": email, "password": password})
        assert denied >= 400, "Unverified account could log in"
        code = self.code(email, "Your Survivor Island verification code")
        invalid = "0" * len(code) if code != "0" * len(code) else "1" * len(code)
        denied, _ = self.auth("verify", {"email": email, "token": invalid, "type": "email"})
        assert denied >= 400, "Invalid verification code was accepted"
        status, user = self.auth("verify", {"email": email, "token": code, "type": "email"})
        assert status == 200 and user.get("access_token"), "Email verification failed"
        return user

    def login(self, email, password):
        status, session = self.auth("token?grant_type=password", {"email": email, "password": password})
        assert status == 200 and session.get("access_token"), "Password login failed"
        return session


def run(backend, snapshot):
    suffix = uuid4().hex
    password = "Temp-Login!" + suffix
    email_a, email_b = [f"phase3b-{label}-{suffix}@example.test" for label in ("a", "b")]
    start = monotonic()
    a = backend.register(email_a, password)
    b = backend.register(email_b, password)
    assert backend.auth("token?grant_type=password", {"email": email_a, "password": "wrong-password"})[0] >= 400
    a = backend.login(email_a, password)
    old = a
    status, a = backend.auth("token?grant_type=refresh_token", {"refresh_token": a["refresh_token"]})
    assert status == 200 and old["refresh_token"] != a["refresh_token"], "Refresh token did not rotate"
    assert backend.auth("token?grant_type=refresh_token", {"refresh_token": "invalid"})[0] >= 400
    assert backend.rpc("list")[0] in (401, 403)
    login_ms = round((monotonic() - start) * 1000)

    save_id, other_id = str(uuid4()), str(uuid4())
    create = {"id": save_id, "expected": 0, "operation": str(uuid4()), "snapshot": snapshot}
    start = monotonic()
    assert backend.rpc("put", create, a) == (200, {"status": "saved", "revision": 1})
    first_upload_ms = round((monotonic() - start) * 1000)
    assert backend.rpc("put", create, a)[1]["revision"] == 1
    altered = {**create, "snapshot": snapshot + " "}
    assert backend.rpc("put", altered, a)[1]["status"] == "operation_mismatch"
    assert backend.rpc("put", {**create, "id": other_id}, b)[1]["status"] == "saved"
    a_items = backend.rpc("list", session=a)[1]
    assert len(a_items) == 1 and a_items[0]["id"] == save_id and "snapshot" not in a_items[0]
    assert backend.rpc("get", {"id": other_id}, a)[1]["status"] == "missing"
    assert backend.rpc("put", {**create, "id": other_id, "expected": 1}, a)[1]["status"] == "missing"
    assert backend.rpc("delete", {"id": other_id, "expected": 1}, a)[1]["status"] == "deleted"
    assert backend.rpc("get", {"id": other_id}, b)[1]["status"] == "found"
    for table in ("profiles", "player_settings", "save_slots", "save_revisions"):
        assert backend.request("/rest/v1/" + table, session=a)[0] in (401, 403, 404)
        assert backend.request("/rest/v1/" + table, {"account_id": b["user"]["id"]}, a, "PATCH")[0] in (401, 403, 404)
    assert backend.rpc("put", {**create, "id": str(uuid4()), "guest_import": True}, a)[1]["status"] == "already_imported"
    assert backend.rpc("put", {**create, "snapshot": "x" * 256001}, a)[1]["status"] == "invalid_snapshot"
    assert backend.rpc("put", {**create, "snapshot": "{}"}, a)[1]["status"] == "invalid_snapshot"
    wrapper = json.loads(snapshot)
    payload = json.loads(wrapper["payload"])
    payload["state"]["world"]["camp-2"]["people"] = {}
    bad = json.dumps(payload)
    invalid = json.dumps({"payload": bad, "sha256": hashlib.sha256(bad.encode()).hexdigest()})
    assert backend.rpc("put", {**create, "snapshot": invalid}, a)[1]["status"] == "invalid_snapshot"

    payload = json.loads(wrapper["payload"])
    payload["state"]["tick"] += .5
    bad = json.dumps(payload)
    fractional = json.dumps({"payload": bad, "sha256": hashlib.sha256(bad.encode()).hexdigest()})
    assert backend.rpc("put", {**create, "snapshot": fractional}, a)[1]["status"] == "invalid_snapshot"

    def contender():
        request = {**create, "expected": 1, "operation": str(uuid4())}
        return request, backend.rpc("put", request, a)[1]

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        first, second = list(pool.map(lambda _: contender(), range(2)))
    assert sorted((first[1]["status"], second[1]["status"])) == ["conflict", "saved"]
    winner = first if first[1]["status"] == "saved" else second
    assert backend.rpc("put", winner[0], a)[1] == winner[1], "Lost response safe retry failed"
    for revision in range(2, 6):
        request = {**create, "expected": revision, "operation": str(uuid4())}
        assert backend.rpc("put", request, a)[1]["revision"] == revision + 1
    assert backend.rpc("get", {"id": save_id, "revision": 3}, a)[1]["status"] == "missing"
    for revision in (4, 5, 6):
        assert backend.rpc("get", {"id": save_id, "revision": revision}, a)[1]["snapshot"] == snapshot
    assert backend.rpc("put", winner[0], a)[1]["status"] == "conflict", "Pruned retry created another revision"
    assert backend.rpc("delete", {"id": save_id, "expected": 5}, a)[1]["status"] == "conflict"
    assert backend.rpc("settings", {"expected": 0, "preferences": {
        "run": False, "camera_steering": True, "sensitivity": "0.65"}}, a)[1]["status"] == "saved"
    assert backend.rpc("settings", {"expected": 0}, a)[1]["status"] == "conflict"
    assert backend.rpc("profile", session=b)[1]["settings_revision"] == 0

    assert backend.auth("recover", {"email": email_a})[0] in (200, 204)
    code = backend.code(email_a, "Your Survivor Island recovery code")
    status, recovery = backend.auth("verify", {"email": email_a, "token": code, "type": "recovery"})
    assert status == 200, "Recovery verification failed"
    new_password = "Changed-Login!" + suffix
    assert backend.auth("user", {"password": new_password}, recovery, "PUT")[0] == 200
    assert backend.auth("token?grant_type=password", {"email": email_a, "password": password})[0] >= 400
    a = backend.login(email_a, new_password)
    assert backend.auth("logout?scope=local", {}, a)[0] in (200, 204)
    assert backend.rpc("list", session=a)[0] in (401, 403), "Logged-out JWT retained save access"
    a = backend.login(email_a, new_password)
    path = "/functions/v1/delete-player"
    assert backend.request(path, {"password": new_password})[0] in (401, 403)
    assert backend.request(path, {"password": new_password, "user": b["user"]["id"]}, a)[0] == 400
    assert backend.request(path, {"password": "wrong-password"}, a)[0] == 403
    assert backend.request(path, {"password": new_password}, a)[0] == 200
    assert backend.rpc("list", session=a)[0] in (401, 403), "Deleted account retained access"
    assert backend.auth("token?grant_type=password", {"email": email_a, "password": new_password})[0] >= 400
    assert backend.rpc("get", {"id": other_id}, b)[1]["status"] == "found"
    assert backend.request(path, {"password": password}, b)[0] == 200
    print(f"Auth, Mailpit, authorization, recovery, deletion, concurrency and retention passed. "
          f"Fixture {len(snapshot.encode()):,} bytes, first upload {first_upload_ms} ms, "
          f"two registrations plus login and refresh {login_ms} ms.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("--url", default="http://127.0.0.1:54321")
    parser.add_argument("--mailpit", default="http://127.0.0.1:54324")
    options = parser.parse_args()
    if not options.url.startswith(("http://127.0.0.1:", "http://localhost:")):
        parser.error("This script creates and deletes disposable accounts on a local stack only")
    run(Backend(options.url, os.environ["SURVIVOR_TEST_PUBLIC_KEY"], options.mailpit),
        options.snapshot.read_text())
