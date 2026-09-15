#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="$project_dir/dist/Macomon.app"
version="$(plutil -extract CFBundleShortVersionString raw "$project_dir/support/Info.plist")"
dmg_path="$project_dir/dist/Macomon-${version}-Installer.dmg"
volume_name="Macomon $version"
work_dir="$(mktemp -d /tmp/macomon-installer.XXXXXX)"
work_dir="${work_dir:A}"
mount_dir=""
read_write_dmg="$work_dir/Macomon-rw.dmg"

cleanup() {
    if [[ -n "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
    fi
    if [[ "$work_dir" == /tmp/macomon-installer.* && -d "$work_dir" ]]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT

"$script_dir/build-app.sh"

hdiutil create \
    -size 32m \
    -fs HFS+ \
    -volname "$volume_name" \
    "$read_write_dmg"
mount_dir="$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$read_write_dmg" | awk -F '\t' '/Apple_HFS/ {print $NF; exit}')"

if [[ -z "$mount_dir" || ! -d "$mount_dir" ]]; then
    echo "Das Installer-Volume konnte nicht eingebunden werden." >&2
    exit 1
fi

cp -R "$app_dir" "$mount_dir/Macomon.app"
ln -s /Applications "$mount_dir/Programme"
mkdir -p "$mount_dir/.background"
cp "$project_dir/support/assets/dmg-background.png" "$mount_dir/.background/dmg-background.png"
SetFile -a V "$mount_dir/.background"

osascript "$script_dir/layout-installer.applescript" "$volume_name" "$mount_dir"
sync
hdiutil detach "$mount_dir"

hdiutil convert "$read_write_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$dmg_path"

echo "$dmg_path"
