#!/usr/bin/env bash
set -euo pipefail

version=4.7.2
release="$version-stable"
base_url="https://github.com/godotengine/godot-builds/releases/download/$release"
editor_name="Godot_v${release}_linux.x86_64"
template_name=web_nothreads_release.zip
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$version.stable"
editor="$bin_dir/godot-$version"
template="$template_dir/$template_name"
template_sha=d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

download() {
  local asset="$1"
  local checksum="$2"
  curl --fail --location --retry 3 --silent --show-error \
    "$base_url/$asset" --output "$work_dir/$asset"
  printf '%s  %s\n' "$checksum" "$work_dir/$asset" | sha256sum --check --status
}

if [[ ! -x "$editor" ]] || [[ "$("$editor" --version)" != "$version.stable.official.ed1daf0bf" ]]; then
  download "$editor_name.zip" cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
  unzip -q "$work_dir/$editor_name.zip" -d "$work_dir"
  mkdir -p "$bin_dir"
  install -m 755 "$work_dir/$editor_name" "$editor"
fi

if ! printf '%s  %s\n' "$template_sha" "$template" | sha256sum --check --status 2>/dev/null; then
  archive="Godot_v${release}_export_templates.tpz"
  download "$archive" f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011
  unzip -p "$work_dir/$archive" "templates/$template_name" > "$work_dir/$template_name"
  printf '%s  %s\n' "$template_sha" "$work_dir/$template_name" | sha256sum --check
  mkdir -p "$template_dir"
  install -m 644 "$work_dir/$template_name" "$template"
fi

"$editor" --version
