#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
asset_dir="$project_dir/support/assets"
work_dir="$(mktemp -d /tmp/macomon-brand.XXXXXX)"
iconset_dir="$work_dir/Macomon.iconset"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"

cleanup() {
    if [[ "$work_dir" == /tmp/macomon-brand.* && -d "$work_dir" ]]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    developer_dir="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p "$asset_dir"
DEVELOPER_DIR="$developer_dir" xcrun swift "$script_dir/BrandAssets.swift" \
    "$project_dir/pets/kleiner_hund/default_idle_8fps.gif" \
    "$asset_dir/macomon-app-icon-source.png" \
    "$asset_dir/macomon-dog-mark.png" \
    "$asset_dir/dmg-background-source.png" \
    "$asset_dir/dmg-background.png" \
    "$iconset_dir"

iconutil -c icns "$iconset_dir" -o "$asset_dir/Macomon.icns"
