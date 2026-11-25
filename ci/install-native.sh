#!/usr/bin/env bash
set -euo pipefail
version=4.7.2
mkdir -p build/native-tools
cd build/native-tools
base="https://github.com/godotengine/godot-builds/releases/download/$version-stable"
if [[ "$OSTYPE" == darwin* ]]; then
  curl -fLsS "$base/Godot_v$version-stable_macos.universal.zip" -o editor.zip
  unzip -qo editor.zip
  export GODOT_BIN="$PWD/Godot.app/Contents/MacOS/Godot"
else
  export GODOT_BIN="$(command -v godot)"
fi
test "$("$GODOT_BIN" --version)" = 4.7.2.stable.official.ed1daf0bf
curl -fLsS "$base/Godot_v$version-stable_export_templates.tpz" -o templates.tpz
echo "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011  templates.tpz" | shasum -a 256 -c -
unzip -qo templates.tpz
if [[ "$OSTYPE" == darwin* ]]; then
  target="$HOME/Library/Application Support/Godot/export_templates/$version.stable"
else
  target="$HOME/.local/share/godot/export_templates/$version.stable"
fi
mkdir -p "$target"
cp -R templates/. "$target/"
echo "GODOT_BIN=$GODOT_BIN" >> "$GITHUB_ENV"
