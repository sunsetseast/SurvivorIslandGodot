#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-${XDG_BIN_HOME:-$HOME/.local/bin}/godot-4.7.2}"
test "$("$godot" --version)" = "4.7.2.stable.official.ed1daf0bf"
bake="${TONSAI_SERVER_BAKE:-$PWD/build/tonsai-bake-project}"
if [[ -z "${TONSAI_SERVER_BAKE:-}" ]]; then
  GODOT_BIN="$godot" TONSAI_PREPARE_SERVER=only bash ci/build-tonsai.sh
fi
stage="$PWD/build/server"
rm -rf "$stage"
mkdir -p "$stage"/{application/connected,controllers,server,simulation,multiplayer,world,tonsai/generated}
cp server/*.gd "$stage/server/"
cp application/connected/supabase_transport.gd "$stage/application/connected/"
cp controllers/physical_motor.gd "$stage/controllers/"
cp simulation/{camp_simulation,game_state_data,season_catalog,season_simulation}.gd "$stage/simulation/"
cp multiplayer/wire.gd "$stage/multiplayer/"
cp world/water_surface.gd "$stage/world/"
cp tonsai/site_data.gd "$stage/tonsai/"
cp "$bake"/tonsai/generated/{layout.json,heightfield.bin,navigation.res,server_collision.scn} "$stage/tonsai/generated/"
cat > "$stage/project.godot" <<'GODOT'
config_version=5

[application]
config/name="Survivor Island Dedicated Server"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]
renderer/rendering_method="gl_compatibility"

[navigation]
3d/default_cell_size=0.2
3d/default_cell_height=0.1
3d/merge_rasterizer_cell_scale=0.2

[physics]
3d/default_gravity=18.0

[threading]
worker_pool/max_threads=2
GODOT

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
"$godot" --headless --path "$stage" --editor --import --quit 2>&1 | tee "$log"
"$godot" --headless --path "$stage" --script res://server/main.gd --check-only 2>&1 | tee -a "$log"
! grep -Eq 'ERROR:|SCRIPT ERROR:' "$log"
