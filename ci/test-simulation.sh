#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/marooning"
cp marooning/session.gd marooning/race.gd marooning/scramble.gd marooning/supply_catalog.gd "$stage/marooning/"
cp -R simulation persistence multiplayer "$stage/"
mkdir -p "$stage/application/selection"
cp application/selection/catalog.gd application/selection/setup.gd application/selection/season_configuration.gd "$stage/application/selection/"
cp tests/living_camp_test.gd tests/opening_test.gd tests/opening_fixture.gd tests/foundation_test.gd tests/season_compatibility_test.gd "$stage/"
printf 'config_version=5\n[application]\nconfig/name="Survivor Simulation Test"\n' > "$stage/project.godot"
"$godot" --headless --path "$stage" --editor --import --quit 2>&1 | tee "$stage/import.log"
"$godot" --headless --path "$stage" --script res://foundation_test.gd 2>&1 | tee "$stage/test.log"
"$godot" --headless --path "$stage" --script res://season_compatibility_test.gd 2>&1 | tee "$stage/compatibility.log"
"$godot" --headless --path "$stage" --script res://opening_test.gd 2>&1 | tee "$stage/opening.log"
"$godot" --headless --path "$stage" --script res://living_camp_test.gd 2>&1 | tee "$stage/living.log"
! grep -Eq 'ERROR:|SCRIPT ERROR:' "$stage/"*.log
