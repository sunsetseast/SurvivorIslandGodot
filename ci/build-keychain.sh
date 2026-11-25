#!/usr/bin/env bash
set -euo pipefail
root="$PWD"
source_dir="$root/build/godot-headers"
git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git "$source_dir"
# A plugin uses the same C++ core ABI as its export template.
test "$(git -C "$source_dir" rev-parse --short=9 HEAD)" = ed1daf0bf
out="$root/build/tonsai-project/ios/plugins"
mkdir -p "$out"
for sdk in iphoneos iphonesimulator; do
  triple=arm64-apple-ios15.0
  [[ "$sdk" != iphonesimulator ]] || triple=arm64-apple-ios15.0-simulator
  xcrun --sdk "$sdk" clang++ -target "$triple" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -std=c++17 -fobjc-arc -fblocks -fno-exceptions -DIOS_ENABLED -DUNIX_ENABLED \
    -DNDEBUG -DPTRCALL_ENABLED -I"$source_dir" -c native/ios/survivor_keychain.mm -o "build/keychain-$sdk.o"
  xcrun ar rcs "build/keychain-$sdk.a" "build/keychain-$sdk.o"
done
xcodebuild -create-xcframework -library build/keychain-iphoneos.a -library build/keychain-iphonesimulator.a \
  -output "$out/survivor_keychain.xcframework"
cp native/ios/survivor_keychain.gdip "$out/"
