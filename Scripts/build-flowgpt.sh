#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p release/flowgpt
Scripts/test.sh > release/flowgpt/tests.log 2>&1
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors > release/flowgpt/build.log 2>&1
build_path=$(swift build -c release --arch arm64 --show-bin-path)
stage=$(mktemp -d "$project_dir/release/flowgpt/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/FlowGpt.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$build_path/FlowGpt" "$app/Contents/MacOS/FlowGpt"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Docs/FLOWGPT_10.md "$app/Contents/Resources/UserGuide.md"
swift Scripts/make-icon.swift "$stage/Flow.iconset"
iconutil -c icns "$stage/Flow.iconset" -o "$app/Contents/Resources/Flow.icns"
codesign --force --sign "${FLOW_SIGNING_IDENTITY:--}" --options runtime --entitlements Resources/Entitlements.plist "$app"
codesign --verify --strict --verbose=2 "$app"
"$app/Contents/MacOS/FlowGpt" --self-check > release/flowgpt/bundle-check.json
bundle="$project_dir/release/flowgpt/FlowGpt.app"
if [[ -e "$bundle" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" == 'in.vardaan.flow' ]] || exit 1
    rm -rf "$bundle"
fi
ditto "$app" "$bundle"
Scripts/package-flowgpt.sh
