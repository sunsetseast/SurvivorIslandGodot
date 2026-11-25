#!/usr/bin/env bash
set -euo pipefail
root="$PWD"
source_dir="$root/build/godot-headers"
git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git "$source_dir"
# A plugin uses the same C++ core ABI as its export template.
test "$(git -C "$source_dir" rev-parse --short=9 HEAD)" = ed1daf0bf
# Generate the public core headers required by the static plugin ABI.
python3 - "$source_dir" <<'GEN'
import os, sys
from pathlib import Path
os.chdir(sys.argv[1])
sys.path.insert(0, os.getcwd())
from core.extension import make_interface_header
from core.object import make_virtuals
make_interface_header.run(["core/extension/gdextension_interface.gen.h"],
    ["core/extension/gdextension_interface.json"], {})
make_virtuals.run(["core/object/gdvirtual.gen.h"], [], {})
# Default official templates do not disable any core classes.
Path("core/disabled_classes.gen.h").write_text("// Default official template: no disabled classes.\n")
GEN
out="$root/build/tonsai-project/ios/plugins"
mkdir -p "$out"
for sdk in iphoneos iphonesimulator; do
  triple=arm64-apple-ios15.0
  [[ "$sdk" != iphonesimulator ]] || triple=arm64-apple-ios15.0-simulator
  xcrun --sdk "$sdk" clang++ -target "$triple" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -std=c++17 -fobjc-arc -fblocks -fno-exceptions -DIOS_ENABLED -DUNIX_ENABLED \
    -DNDEBUG -DPTRCALL_ENABLED -I"$source_dir" -I"$source_dir/platform/ios" -c native/ios/survivor_keychain.mm -o "build/keychain-$sdk.o"
  xcrun ar rcs "build/keychain-$sdk.a" "build/keychain-$sdk.o"
done
xcodebuild -create-xcframework -library build/keychain-iphoneos.a -library build/keychain-iphonesimulator.a \
  -output "$out/survivor_keychain.xcframework"
cp native/ios/survivor_keychain.gdip "$out/"
