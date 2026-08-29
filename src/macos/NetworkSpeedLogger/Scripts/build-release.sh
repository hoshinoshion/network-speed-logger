#!/bin/bash

set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
repository_root=$(cd "$project_dir/../../.." && pwd)
source_dir="$project_dir/Sources/NetworkSpeedLogger"
build_dir="$project_dir/.build/release-universal"
dist_dir="$repository_root/dist"
app_path="$dist_dir/NetworkSpeedLogger.app"
dmg_path="$dist_dir/NetworkSpeedLogger.dmg"
version=${1:-0.2.6}

case "$version" in
    *[!0-9.]*|'')
        echo "Version must contain only digits and dots." >&2
        exit 2
        ;;
esac

mkdir -p "$build_dir" "$dist_dir"
rm -rf "$build_dir/NetworkSpeedLogger.app" "$build_dir/AppIcon.iconset" "$app_path"
rm -f "$dmg_path"

sdk_path=$(xcrun --sdk macosx --show-sdk-path)
source_files=()
while IFS= read -r -d '' source_file; do
    source_files+=("$source_file")
done < <(find "$source_dir" -type f -name '*.swift' -print0 | sort -z)

if [ "${#source_files[@]}" -eq 0 ]; then
    echo "No Swift source files were found." >&2
    exit 1
fi

for architecture in arm64 x86_64; do
    xcrun swiftc \
        -parse-as-library \
        -O \
        -whole-module-optimization \
        -module-name NetworkSpeedLogger \
        -target "${architecture}-apple-macos13.0" \
        -sdk "$sdk_path" \
        "${source_files[@]}" \
        -framework AppKit \
        -framework Charts \
        -framework SystemConfiguration \
        -o "$build_dir/NetworkSpeedLogger-$architecture"
done

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
lipo -create \
    "$build_dir/NetworkSpeedLogger-arm64" \
    "$build_dir/NetworkSpeedLogger-x86_64" \
    -output "$app_path/Contents/MacOS/NetworkSpeedLogger"
chmod 755 "$app_path/Contents/MacOS/NetworkSpeedLogger"

cp "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_path/Contents/Info.plist"
while IFS= read -r -d '' localization_directory; do
    cp -R "$localization_directory" "$app_path/Contents/Resources/"
done < <(find "$project_dir/Resources" -maxdepth 1 -type d -name '*.lproj' -print0)

iconset_path="$build_dir/AppIcon.iconset"
xcrun swift "$project_dir/Scripts/render-icon.swift" "$iconset_path"
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/AppIcon.icns"

# An ad-hoc signature is not a Developer ID signature. It keeps the Universal
# bundle internally consistent while the project intentionally remains unsigned.
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
lipo "$app_path/Contents/MacOS/NetworkSpeedLogger" -verify_arch arm64 x86_64

dmg_stage=$(mktemp -d "${TMPDIR:-/tmp}/network-speed-logger-dmg.XXXXXX")
cleanup() {
    rm -rf "$dmg_stage"
}
trap cleanup EXIT

cp -R "$app_path" "$dmg_stage/NetworkSpeedLogger.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create \
    -volname "Network Speed Logger" \
    -srcfolder "$dmg_stage" \
    -ov \
    -format UDZO \
    "$dmg_path"
hdiutil verify "$dmg_path"

echo "Created $app_path"
echo "Created $dmg_path"
