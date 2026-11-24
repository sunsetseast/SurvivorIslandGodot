#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R simulation persistence "$stage/"
cp tests/foundation_test.gd "$stage/"
printf 'config_version=5\n[application]\nconfig/name="Survivor Simulation Test"\n' > "$stage/project.godot"
"$godot" --headless --path "$stage" --editor --import --quit 2>&1 | tee "$stage/import.log"
"$godot" --headless --path "$stage" --script res://foundation_test.gd 2>&1 | tee "$stage/test.log"
! grep -Eq 'ERROR:|SCRIPT ERROR:' "$stage/"*.log
