#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
test "$("$godot" --version)" = "4.7.2.stable.official.ed1daf0bf"
if [[ "${GITHUB_ACTIONS:-}" == "true" && ( -n "${SURVIVOR_PRIVATE_CAST:-}" || -n "${SURVIVOR_PRIVATE_UI:-}" || -n "${SURVIVOR_PRIVATE_LOGO:-}" ) ]]; then
  echo "Private staging is forbidden in public Actions artifacts." >&2
  exit 1
fi
stage="$PWD/build/tonsai-project"
output="$PWD/build/tonsai"
if [[ "${TONSAI_PREPARE_SERVER:-0}" == "only" ]]; then
  stage="$PWD/build/tonsai-bake-project"
  output="$PWD/build/tonsai-bake-unused"
fi
rm -rf "$stage" "$output"
mkdir -p "$stage/tools/marooning" "$stage/character_lab/assets" "$stage/tests" "$stage/tools/tonsai" "$output"
touch build/.gdignore
cp -R marooning controllers simulation application persistence multiplayer diagnostics "$stage/"
mkdir -p "$stage/world/assets"
cp world/water_surface.gd world/water.gdshader world/camp_fire.gd world/fire_flipbook.gdshader "$stage/world/"
for asset in surface-swimming.res sunflowers-sky.jpg kloofendal-clear.jpg flame02.webp water-ripple.png seating_log.glb seat_stump.glb shore_rock.glb; do
  cp "world/assets/$asset" "$stage/world/assets/"
done
mkdir -p "$stage/tonsai/shaders" "$stage/tonsai/generated"
cp tonsai/*.gd tonsai/*.tscn "$stage/tonsai/"
cp tonsai/shaders/*.gdshader "$stage/tonsai/shaders/"
cp tools/marooning/*.gd "$stage/tools/marooning/"
cp tools/tonsai/bake_nav.gd tools/tonsai/bake_server_collision.gd "$stage/tools/tonsai/"
cp tests/shallow_exit_test.gd tests/vessel_progress_test.gd tests/traffic_metrics.gd tests/marooning_pose_test.gd tests/navigation_recovery_test.gd tests/native_marooning_touch_test.gd tests/session_test.gd tests/stroke_impulse_test.gd tests/moving_board_test.gd tests/ship_access_test.gd tests/concurrent_physical_test.gd tests/deck_layout_test.gd tests/supply_visual_test.gd tests/deck_traffic_test.gd tests/deposit_test.gd tests/race_ui_test.gd tests/race_balance.gd tests/race_test.gd tests/race_physical_test.gd tests/scramble_test.gd tests/marooning_test.gd tests/phase4c_test.gd tests/phase4c_camp_test.gd tests/tonsai_test.gd tests/application_test.gd tests/credential_test.gd tests/benchmark_test.gd tests/title_test.gd tests/selection_test.gd "$stage/tests/"
cp character_lab/actor.gd "$stage/character_lab/"
cp character_lab/assets/maeve.glb "$stage/character_lab/assets/"
cp icon.svg "$stage/" 2>/dev/null || true
# This stage is the sole export root. Source references and private likeness
# files are outside the allowlist. Neither Phase 0 nor the lab is reconfigured.
# Optional approved art/font stay outside Git and public artifacts.
if [[ -n "${SURVIVOR_PRIVATE_UI:-}" ]]; then
  python3 tools/tonsai/stage_private_ui.py "$SURVIVOR_PRIVATE_UI" "$stage/private_brand"
fi
if [[ -n "${SURVIVOR_PRIVATE_LOGO:-}" ]]; then
  mkdir -p "$stage/private_brand"
  cp "$SURVIVOR_PRIVATE_LOGO" "$stage/private_brand/logo.png"
fi
if [[ -n "${SURVIVOR_PRIVATE_CAST:-}" ]]; then
  test -f "$SURVIVOR_PRIVATE_CAST/.private-cast-stage"
  mkdir -p "$stage/private_cast"
  cp -R "$SURVIVOR_PRIVATE_CAST"/. "$stage/private_cast/"
fi
cp project.godot "$stage/"
# Godot4.7.2 can notify the SceneTree from a font-import worker and crash.
# Serialise this disposable stage's import; gameplay threading is unchanged.
printf '\n[editor]\nimport/use_multiple_threads=false\n' >> "$stage/project.godot"
printf '\n[marooning_build]\nimplementation_sha="%s"\n' "$(git rev-parse HEAD)" >> "$stage/project.godot"
if [[ "${TONSAI_STAGE_ONLY:-0}" == 1 ]]; then
  cp native/development-icon.svg "$stage/icon.svg"
  python3 - "$stage/project.godot" <<'NATIVE'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace("[application]", '[application]\nconfig/icon="res://icon.svg"').replace("[rendering]", "[rendering]\ntextures/vram_compression/import_etc2_astc=true"))
NATIVE
fi
if [[ "${SURVIVOR_DIAGNOSTICS:-0}" == 1 ]]; then
  printf '\n[survivor_diagnostics]\nenabled=true\nbuild_sha="%s"\n' "$(git rev-parse HEAD)" >> "$stage/project.godot"
fi
if [[ -n "${SURVIVOR_WSS_ENDPOINT:-}" ]]; then
  if [[ ! "$SURVIVOR_WSS_ENDPOINT" =~ ^wss://[a-zA-Z0-9.-]+(:[0-9]+)?/ws$ ]]; then
    echo "SURVIVOR_WSS_ENDPOINT must be wss://your-host/ws" >&2
    exit 1
  fi
  printf '\n[survivor]\nmultiplayer/endpoint="%s"\n' "$SURVIVOR_WSS_ENDPOINT" >> "$stage/project.godot"
fi
sed -e 's|^include_filter=""|include_filter="tonsai/generated/layout.json,tonsai/generated/heightfield.bin,application/presentation/fonts/LICENSE.txt,private_cast/catalog.json,controllers/third_party/PHANTOM_CAMERA_LICENSE.txt"|' \
    -e 's|^exclude_filter=""|exclude_filter="tests/*,tools/*,tonsai/generated/server_collision.scn"|' \
    -e 's|html/experimental_virtual_keyboard=false|html/experimental_virtual_keyboard=true|' \
    export_presets.cfg > "$stage/export_presets.cfg"
if [[ -n "${TONSAI_REFERENCE:-}" ]]; then
  node tools/tonsai/prepare.mjs "$TONSAI_REFERENCE"
else
  node tools/tonsai/prepare.mjs
fi
for asset in layout.json heightfield.bin reconstruction-low.glb landmarks-low.glb limestone.glb coastal-tree.glb palms.glb fern_02.glb sand_02-diff.jpg brown_mud_leaves_01-diff.jpg rock_06_diff_1k.jpg; do
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
run_godot --script res://tools/marooning/bake_nav.gd
run_godot --script res://tools/tonsai/bake_nav.gd
if [[ "${TONSAI_PREPARE_SERVER:-0}" != 0 ]]; then
  run_godot --script res://tools/tonsai/bake_server_collision.gd
  if [[ "${TONSAI_PREPARE_SERVER:-0}" == "only" ]]; then
    exit 0
  fi
fi
cp "$stage/tonsai/generated/navigation.res" tonsai/generated/navigation.res
if [[ "${TONSAI_STAGE_ONLY:-0}" == 1 ]]; then exit 0; fi
run_godot --script res://tests/scramble_test.gd
run_godot --script res://tests/deck_layout_test.gd
run_godot --script res://tests/supply_visual_test.gd
run_godot --script res://tests/deposit_test.gd
run_godot --fixed-fps 60 --script res://tests/deck_traffic_test.gd
run_godot --fixed-fps 60 --script res://tests/vessel_progress_test.gd
run_godot --fixed-fps 60 --script res://tests/shallow_exit_test.gd
run_godot --fixed-fps 60 --script res://tests/marooning_pose_test.gd
run_godot --fixed-fps 60 --script res://tests/navigation_recovery_test.gd
run_godot --script res://tests/session_test.gd
run_godot --script res://tests/stroke_impulse_test.gd
run_godot --script res://tests/moving_board_test.gd
run_godot --fixed-fps 60 --script res://tests/ship_access_test.gd
run_godot --script res://tests/race_test.gd
run_godot --script res://tests/race_ui_test.gd
run_godot --script res://tests/race_balance.gd
run_godot --fixed-fps 60 --script res://tests/race_physical_test.gd
run_godot --fixed-fps 60 --script res://tests/marooning_test.gd
run_godot --fixed-fps 60 --script res://tests/tonsai_test.gd
run_godot --fixed-fps 60 --script res://tests/application_test.gd
run_godot --script res://tests/selection_test.gd
run_godot --script res://tests/title_test.gd
run_godot --script res://tests/credential_test.gd
run_godot --script res://tests/benchmark_test.gd
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
assert 'Survivor Island' in html
PY
touch "$output/.nojekyll"
cp controllers/third_party/PHANTOM_CAMERA_LICENSE.txt "$output/third-party-notices.txt"
cat marooning/assets/PROVENANCE.txt >> "$output/third-party-notices.txt"
