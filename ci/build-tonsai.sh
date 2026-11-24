#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
test "$("$godot" --version)" = "4.7.2.stable.official.ed1daf0bf"
stage="$PWD/build/tonsai-project"
output="$PWD/build/tonsai"
rm -rf "$stage" "$output"
mkdir -p "$stage/character_lab/assets" "$stage/tests" "$stage/tools/tonsai" "$output"
touch build/.gdignore
cp -R controllers simulation "$stage/"
mkdir -p "$stage/tonsai/shaders" "$stage/tonsai/generated"
cp tonsai/*.gd tonsai/*.tscn "$stage/tonsai/"
cp tonsai/shaders/*.gdshader "$stage/tonsai/shaders/"
cp tools/tonsai/bake_nav.gd "$stage/tools/tonsai/"
cp tests/tonsai_test.gd "$stage/tests/"
cp character_lab/actor.gd "$stage/character_lab/"
cp character_lab/assets/maeve.glb "$stage/character_lab/assets/"
cp icon.svg "$stage/" 2>/dev/null || true
# This stage is the sole export root. Source references and private likeness
# files are outside the allowlist. Neither Phase 0 nor the lab is reconfigured.
sed -e 's|res://scenes/main.tscn|res://tonsai/camp.tscn|' \
    -e 's|Survivor Island — Phase 0|Survivor Island — Tonsai Beach|' \
    -e 's|window/stretch/aspect="[^"]*"|window/stretch/aspect="expand"|' project.godot > "$stage/project.godot"
sed 's|^include_filter=""|include_filter="tonsai/generated/layout.json,tonsai/generated/heightfield.bin"|' \
    export_presets.cfg | sed 's|encryption_include_filter="tonsai[^"]*"|encryption_include_filter=""|' > "$stage/export_presets.cfg"
if [[ -n "${TONSAI_REFERENCE:-}" ]]; then
  node tools/tonsai/prepare.mjs "$TONSAI_REFERENCE"
else
  node tools/tonsai/prepare.mjs
fi
for asset in layout.json heightfield.bin reconstruction-low.glb landmarks-low.glb limestone.glb coastal-tree.glb palms.glb fern_02.glb sand_02-diff.jpg brown_mud_leaves_01-diff.jpg rock_06_diff_1k.jpg tropical-clouds.png; do
  cp "tonsai/generated/$asset" "$stage/tonsai/generated/"
done
run_godot() {
  local log
  log="$(mktemp)"
  local result=0
  "$godot" --headless --path "$stage" "$@" 2>&1 | tee "$log" || result=1
  if grep -Eq 'ERROR:|SCRIPT ERROR:' "$log"; then result=1; fi
  rm -f "$log"
  return "$result"
}
run_godot --editor --import --quit
run_godot --script res://tools/tonsai/bake_nav.gd
cp "$stage/tonsai/generated/navigation.res" tonsai/generated/navigation.res
run_godot --fixed-fps 60 --script res://tests/tonsai_test.gd
run_godot --export-release Web "$output/index.html"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
for file, magic in {"index.html": b"<!DOCTYPE", "index.js": b"", "index.pck": b"GDPC", "index.wasm": b"\x00asm"}.items():
    path = root / file
    with path.open("rb") as handle:
        header = handle.read(len(magic))
    assert path.stat().st_size > 0 and header == magic, file
    print(f"{file}: {path.stat().st_size:,} bytes")
html = (root / "index.html").read_text()
assert re.search(r"GODOT_THREADS_ENABLED\s*=\s*false", html)
assert 'Tonsai' in html
PY
touch "$output/.nojekyll"
