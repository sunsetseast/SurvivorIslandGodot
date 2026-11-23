#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
output="$PWD/build/web"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run_godot() {
  # Godot can report a runtime error while still returning exit code zero.
  "$godot" --headless --path . "$@" 2>&1 | tee "$log"
  if grep -Eq 'ERROR:|SCRIPT ERROR:' "$log"; then
    return 1
  fi
}

"$godot" --version
mkdir -p build
touch build/.gdignore
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
