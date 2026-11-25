"""One bounded simulator attempt; no signing or physical-device installation."""
import json
import pathlib
import subprocess as sp

def run(*args):
    return sp.check_output(args, text=True, timeout=120)
devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))
device = next(d for ds in devices["devices"].values() for d in ds if "iPhone" in d["name"])
udid = device["udid"]
if device["state"] != "Booted":
    run("xcrun", "simctl", "boot", udid)
run("xcrun", "simctl", "bootstatus", udid, "-b")
app = next(pathlib.Path("build/ios-simulator/Build/Products").glob("*iphonesimulator/SurvivorIsland.app"))
run("xcrun", "simctl", "install", udid, str(app))
print(run("xcrun", "simctl", "launch", udid, "org.survivorisland.prototype"))
