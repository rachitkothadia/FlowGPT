#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
app="$project_dir/release/flowgpt/FlowGpt.app"
[[ -d "$app" ]] || { print -u2 'Build FlowGpt first'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
stage=$(mktemp -d "$project_dir/release/flowgpt/.image.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/FlowGpt.app"
ln -s /Applications "$stage/Applications"
cp Docs/MAC_11.md "$stage/Read Me.md"
dmg="$project_dir/FlowGpt-$version-arm64.dmg"
hdiutil create -ov -volname "Install FlowGpt $version" -srcfolder "$stage" -format UDZO "$dmg"
hdiutil verify "$dmg"
shasum -a 256 "${dmg:t}" > release/flowgpt/SHA256SUMS.txt
print "Installer: $dmg"
