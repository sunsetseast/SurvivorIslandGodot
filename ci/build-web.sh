#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
stage="$PWD/build/phase0-project"
output="$PWD/build/web"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run_godot() {
  # Godot can report a runtime error while still returning exit code zero.
  "$godot" --headless --path "$stage" "$@" 2>&1 | tee "$log"
  if grep -Eq 'ERROR:|SCRIPT ERROR:' "$log"; then
    return 1
  fi
}

"$godot" --version
mkdir -p build
touch build/.gdignore
rm -rf "$stage"
mkdir -p "$stage/tests"
cp -R scenes scripts "$stage/"
cp icon.svg "$stage/" 2>/dev/null || true
cp tests/smoke_test.gd "$stage/tests/"
sed -e 's|res://application/game_app.tscn|res://scenes/main.tscn|' \
    -e 's|config/name=.*|config/name="Survivor Island — Phase 0"|' project.godot > "$stage/project.godot"
sed 's|^exclude_filter=""|exclude_filter="tests/*"|' export_presets.cfg > "$stage/export_presets.cfg"
run_godot --editor --import --quit
run_godot --script res://tests/smoke_test.gd
rm -rf "$output"
mkdir -p "$output"
run_godot --export-release Web "$output/index.html"
for file in index.html index.js index.wasm index.pck; do
  test -s "$output/$file" || { echo "Missing Web export file: $file" >&2; exit 1; }
done
touch "$output/.nojekyll"
printf 'Web export ready in %s\n' "$output"
