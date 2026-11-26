#!/usr/bin/env bash
# Requires gltf-transform CLI 4.2.1 and KTX-Software 4.4.2 on PATH.
set -euo pipefail
cd "$(dirname "$0")/../.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl --fail --location --max-time 90 https://tevy.dev/models/galleon/v1/lod0.glb -o "$work/source.glb"
printf '30d6c04f6b664c8e8c5ea20383f6abc53e7f70eb5e0f42578b53e7ef5a54655d  %s\n' "$work/source.glb" | sha256sum --check --status
gltf-transform dequantize "$work/source.glb" "$work/dequant.glb"
gltf-transform ktxdecompress "$work/dequant.glb" "$work/decoded.glb"
gltf-transform resize "$work/decoded.glb" "$work/1k.glb" --width 1024 --height 1024
# Inspect/review provenance and changed upstream bytes before replacing this file.
cp "$work/1k.glb" marooning/assets/galleon.glb
sha256sum marooning/assets/galleon.glb
