#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
stage="$PWD/build/lab-project"
output="$PWD/build/character-lab"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run_godot() {
  "$godot" --headless --path "$stage" "$@" 2>&1 | tee "$log"
  ! grep -Eq 'ERROR:|SCRIPT ERROR:' "$log"
}

test "$("$godot" --version)" = "4.7.2.stable.official.ed1daf0bf"
python3 character_lab/tools/validate_glb.py character_lab/assets/maeve.glb
rm -rf "$stage" "$output"
mkdir -p "$stage/character_lab/assets" "$stage/scripts" "$stage/tests" "$output"
touch build/.gdignore
sed -e 's|res://application/game_app.tscn|res://character_lab/lab.tscn|' \
    -e 's|config/name=.*|config/name="Survivor Island — Character Lab"|' \
    project.godot > "$stage/project.godot"
cp export_presets.cfg "$stage/"
cp character_lab/*.gd character_lab/*.tscn "$stage/character_lab/"
cp character_lab/assets/maeve.glb "$stage/character_lab/assets/"
cp scripts/touch_hud.gd "$stage/scripts/"
cp tests/character_lab_test.gd "$stage/tests/"
run_godot --editor --import --quit
run_godot --script res://tests/character_lab_test.gd
run_godot --export-release Web "$output/index.html"
python3 - "$output" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
required = {'index.html': b'<!DOCTYPE', 'index.js': None, 'index.wasm': b'\x00asm', 'index.pck': b'GDPC'}
for name, magic in required.items():
    path = root / name
    with path.open('rb') as handle:
        header = handle.read(len(magic) if magic else 1)
    if name.endswith('.html'):
        header = header.upper()
    assert header and (magic is None or header == magic), name
    print(f'{name}: {path.stat().st_size:,} bytes')
html = (root / 'index.html').read_text()
assert re.search(r'"fileSizes"\s*:', html), 'HTML file-size map missing'
assert re.search(r'GODOT_THREADS_ENABLED\s*=\s*false', html), 'Expected a single-threaded Web export'
PY
touch "$output/.nojekyll"
