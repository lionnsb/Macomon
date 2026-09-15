#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="$project_dir/dist/Macomon.app"
developer_dir="$(xcode-select -p)"

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    developer_dir="/Applications/Xcode.app/Contents/Developer"
fi

DEVELOPER_DIR="$developer_dir" zsh "$script_dir/generate-brand-assets.sh"

cd "$project_dir"
DEVELOPER_DIR="$developer_dir" swift build -c release
bin_dir="$(DEVELOPER_DIR="$developer_dir" swift build -c release --show-bin-path)"

if [[ "${app_dir:t}" != "Macomon.app" || "${app_dir:h:t}" != "dist" ]]; then
    echo "Unerwarteter Ausgabeordner: $app_dir" >&2
    exit 1
fi

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Macomon" "$app_dir/Contents/MacOS/Macomon"
cp -R "$bin_dir/Macomon_Macomon.bundle" "$app_dir/Contents/Resources/Macomon_Macomon.bundle"
cp "$project_dir/support/assets/Macomon.icns" "$app_dir/Contents/Resources/Macomon.icns"
cp "$project_dir/support/assets/macomon-dog-mark.png" "$app_dir/Contents/Resources/MacomonDogMark.png"
cp "$project_dir/support/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
