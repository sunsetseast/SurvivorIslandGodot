#!/usr/bin/env python3
"""Validate read-only reference checkouts and stage restricted data outside public source.

No model search/download occurs. --approved-model-dir is an explicit external input;
without it model_path is empty. Call this only for an intentional private build.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from PIL import Image, ImageOps

GROUPS = {
    "Physical": ("strength", "speed", "endurance", "dexterity", "balance"),
    "Mental": ("memory", "puzzles", "fortitude", "awareness", "focus"),
    "Social": ("connections", "likeability", "interrogation", "deception", "alliances"),
    "Strategy": ("bigmove", "idolhunt", "idolshare", "honesty", "risk", "aggression", "paratend", "leader"),
    "Camp": ("fishing", "laziness", "firemaking", "campcraft"),
}
ATTRIBUTES = tuple(field for fields in GROUPS.values() for field in fields)
DEFAULT_FIELDS = (
    "health", "threat", "challengeThreat", "teamPlayer", "roles", "firewood", "bamboo",
    "palms", "coconuts", "fish", "fish1", "fish2", "fish3", "water", "hunger", "rest",
    "hasVote", "votePenalty", "extraVotes", "suspicion",
)
# Explicit Phase 4B appearance-only instruction; source seasons and ratings stay intact.
APPEARANCE_OVERRIDES = dict.fromkeys((4, 10, 11, 13, 16, 18), "Heroes vs. Villains")
ROOT = Path(__file__).resolve().parents[2]
GAME_DATA = Path("src/modules/data/GameData.js")
APPROVED = Path("test/fixtures/approved-cast-344.json")
PROTECTED = Path("test/fixtures/protected-cast-main.json")
CALIBRATION = Path("docs/survivor-cast-calibration.md")
CAST = Path("artifacts/survivor-camp-prototype/src/game/character/cast.json")
MATRIX = Path("docs/character-art-bible/CAST_MATRIX.md")
MARKER = ".private-cast-stage"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def revision(checkout):
    return subprocess.check_output(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
    ).strip()


def read_game_data(checkout):
    script = """import {pathToFileURL} from 'node:url';
const {default:data} = await import(pathToFileURL(process.argv[1]).href);
process.stdout.write(JSON.stringify(data.getSurvivors()));"""
    return json.loads(subprocess.check_output(
        ["node", "--input-type=module", "-e", script, str(checkout / GAME_DATA)], text=True
    ))


def reconcile(game, prototype):
    """Compare every source field, approved baseline, protected ratings and campcraft."""
    survivors = read_game_data(game)
    cast = json.loads((prototype / CAST).read_text())
    approved = json.loads((game / APPROVED).read_text())
    protected = json.loads((game / PROTECTED).read_text())
    require(cast["version"] == 1, "Unsupported reference cast version")
    require(cast["source"]["revision"] == revision(game), "Reference cast revision is stale")
    require(cast["source"]["file"] == str(GAME_DATA), "Unexpected reference source file")
    require([s["id"] for s in survivors] == list(range(1, 19)), "Expected original ordered IDs 1–18")
    require(survivors == [s["source"] for s in cast["survivors"]], "GameData/cast source mismatch")
    require(len(approved) == len(protected) == len(survivors), "Fixture count mismatch")
    require(all(sum(s["traitClass"] == group for s in survivors) == 6
                for group in ("Physical", "Mental", "Social")), "Expected six of each trait class")
    previous = {s["id"]: s for s in approved}
    # The documented later addition is the only permitted difference from #344.
    craft_rows = re.findall(r"^\| ([^|]+?) \| (\d+) \|", (game / CALIBRATION).read_text().split("## Campcraft validation pass", 1)[1], re.M)
    craft = {name.strip(): int(rating) for name, rating in craft_rows}
    require(len(craft) == 18, "Expected 18 documented campcraft ratings")
    look_rows = re.findall(
        r"^\| (\d+) · \[([^\]]+)\]\([^)]*\) \| S\d+ · ([^|]+?) \|",
        (prototype / MATRIX).read_text(), re.M,
    )
    looks = {int(id_): (name, season.strip()) for id_, name, season in look_rows}
    require(set(looks) == set(range(1, 19)), "Cast matrix IDs mismatch")
    for survivor in survivors:
        id_ = survivor["id"]
        baseline = previous[id_]
        require({k: v for k, v in survivor.items() if k != "campcraft"} == baseline,
                f"Approved baseline mismatch at ID {id_}")
        require(all(survivor[k] == v for k, v in protected[str(id_)].items()),
                f"Protected field mismatch at ID {id_}")
        require(survivor["campcraft"] == craft[survivor["name"]],
                f"Campcraft calibration mismatch at ID {id_}")
        require(looks[id_][0] == survivor["name"], f"Cast matrix identity mismatch at ID {id_}")
        for field in ATTRIBUTES:
            require(type(survivor[field]) is int and 1 <= survivor[field] <= 10,
                    f"Invalid attribute {field} at ID {id_}")
        for group in ("Physical", "Mental", "Social"):
            require(survivor[group.lower()] == sum(survivor[k] for k in GROUPS[group]),
                    f"Invalid {group} aggregate at ID {id_}")
    pins = {
        "game_revision": revision(game), "prototype_revision": revision(prototype),
        "files": {str(p): sha256(game / p) for p in (GAME_DATA, APPROVED, PROTECTED, CALIBRATION)},
    }
    pins["files"].update({str(p): sha256(prototype / p) for p in (CAST, MATRIX)})
    return survivors, looks, pins


def make_entry(survivor, appearance_season, has_model=False):
    id_ = survivor["id"]
    return {
        "id": id_, "name": survivor["name"], "gender": survivor["gender"],
        "trait": survivor["traitClass"], "style": survivor["gameplayStyle"],
        "original_season": survivor["season"], "appearance_season": appearance_season,
        "attributes": {field: survivor[field] for field in ATTRIBUTES},
        "totals": {group: survivor[group.lower()] for group in ("Physical", "Mental", "Social")},
        "defaults": {field: survivor[field] for field in DEFAULT_FIELDS},
        "portrait_path": f"res://private_cast/portraits/{id_}.webp",
        "model_path": f"res://private_cast/models/{id_}.glb" if has_model else "",
    }


def safe_destination(destination, sources):
    destination = destination.resolve()
    require(destination != ROOT / "build", "Use a dedicated private output directory")
    require(not destination.is_relative_to(ROOT) or destination.is_relative_to(ROOT / "build"),
            "Restricted data may only enter the ignored build directory or an external private stage")
    for source in sources:
        require(not destination.is_relative_to(source) and not source.is_relative_to(destination),
                "Stage must be separate from reference inputs")
    require(not destination.exists() or (destination / MARKER).is_file()
            or (destination.is_dir() and not any(destination.iterdir())),
            "Refusing to replace a directory not owned by this staging helper")
    return destination


def stage(game, prototype, destination, approved_model_dir=None):
    game, prototype = game.resolve(), prototype.resolve()
    sources = [game, prototype]
    models = None
    if approved_model_dir is not None:
        models = approved_model_dir.resolve(strict=True)
        require(models.is_dir(), "Approved model input must be a directory")
        require(not any(models.is_relative_to(p) for p in (ROOT, game, prototype)),
                "Models require an explicitly approved external directory")
        sources.append(models)
    destination = safe_destination(destination, sources)
    survivors, looks, pins = reconcile(game, prototype)
    entries = []
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".private-cast-", dir=destination.parent) as temporary:
        output = Path(temporary) / "private_cast"
        (output / "portraits").mkdir(parents=True)
        model_count = 0
        for survivor in survivors:
            id_ = survivor["id"]
            portrait = game / survivor["avatarUrl"]
            require(portrait.resolve().parent == (game / "Assets/Avatars").resolve(),
                    f"Unsafe portrait input at ID {id_}")
            with Image.open(portrait) as image:
                image = ImageOps.exif_transpose(image).convert("RGB")
                image.thumbnail((512, 512), Image.Resampling.LANCZOS)
                image.save(output / "portraits" / f"{id_}.webp", "WEBP", quality=85, method=6)
            pins["files"][survivor["avatarUrl"]] = sha256(portrait)
            has_model = False
            if models is not None:
                model = models / f"survivor-{id_}.glb"
                if model.is_file():
                    require(model.resolve().parent == models, f"Unsafe model input at ID {id_}")
                    with model.open("rb") as handle:
                        require(handle.read(4) == b"glTF", f"Invalid GLB at ID {id_}")
                    (output / "models").mkdir(exist_ok=True)
                    shutil.copyfile(model, output / "models" / f"{id_}.glb")
                    pins["files"][f"approved_models/{model.name}"] = sha256(model)
                    model_count += 1
                    has_model = True
            appearance = APPEARANCE_OVERRIDES.get(id_, looks[id_][1])
            entries.append(make_entry(survivor, appearance, has_model))
        document = {"version": 1, "provenance": pins, "entries": entries}
        (output / "catalog.json").write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
        (output / MARKER).write_text("Restricted private selection stage; never publish in public artifacts.\n")
        if destination.exists():
            shutil.rmtree(destination)
        os.replace(output, destination)
    return {
        "entries": len(entries), "attributes_per_entry": len(ATTRIBUTES),
        "portraits": len(entries), "models": model_count,
        "catalog_sha256": sha256(destination / "catalog.json"), "provenance": pins,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_checkout", type=Path)
    parser.add_argument("prototype_checkout", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--approved-model-dir", type=Path)
    args = parser.parse_args()
    result = stage(args.game_checkout, args.prototype_checkout, args.destination, args.approved_model_dir)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
