#!/bin/zsh
set -euo pipefail

# Build a public FlowGpt release. This intentionally refuses ad hoc signing:
# a downloaded app must be Developer ID signed and notarized for Gatekeeper.
project_dir="${0:A:h:h}"
cd "$project_dir"

: "${FLOW_SIGNING_IDENTITY:?Set FLOW_SIGNING_IDENTITY to your Developer ID Application identity}"
: "${FLOW_NOTARY_PROFILE:?Set FLOW_NOTARY_PROFILE to a stored xcrun notarytool profile}"

if [[ "$FLOW_SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
    print -u2 "FLOW_SIGNING_IDENTITY must be a Developer ID Application certificate."
    exit 2
fi

security find-identity -v -p codesigning | rg -F "$FLOW_SIGNING_IDENTITY" >/dev/null || {
    print -u2 "The requested Developer ID identity is not installed in this keychain."
    exit 2
}
xcrun notarytool history --keychain-profile "$FLOW_NOTARY_PROFILE" >/dev/null

mkdir -p release/distribution
Scripts/test.sh > release/distribution/tests.log 2>&1

stage=$(mktemp -d "$project_dir/release/distribution/.stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors > release/distribution/build-arm64.log 2>&1
swift build -c release --arch x86_64 -Xswiftc -warnings-as-errors > release/distribution/build-x86_64.log 2>&1
arm_path=$(swift build -c release --arch arm64 -Xswiftc -warnings-as-errors --show-bin-path)
x86_path=$(swift build -c release --arch x86_64 -Xswiftc -warnings-as-errors --show-bin-path)

app="$stage/FlowGpt.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$arm_path/FlowGpt" "$x86_path/FlowGpt" -output "$app/Contents/MacOS/FlowGpt"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Docs/MAC_11.md "$app/Contents/Resources/UserGuide.md"
cp Shared/Data/UNICODE-LICENSE.txt "$app/Contents/Resources/CurrencyDataLicense.txt"
swift Scripts/make-icon.swift "$stage/Flow.iconset"
iconutil -c icns "$stage/Flow.iconset" -o "$app/Contents/Resources/Flow.icns"

codesign --force --sign "$FLOW_SIGNING_IDENTITY" --options runtime --entitlements Resources/Entitlements.plist "$app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/FlowGpt"

notarize() {
    local artifact="$1" report="$2"
    xcrun notarytool submit "$artifact" --keychain-profile "$FLOW_NOTARY_PROFILE" --wait --output-format json > "$report"
    local submission_status=$(/usr/bin/plutil -extract status raw -o - "$report")
    [[ "$submission_status" == Accepted ]] || {
        print -u2 "Notarization was not accepted. Inspect $report and retrieve Apple's submission log."
        return 1
    }
}
ditto -c -k --keepParent "$app" "$stage/FlowGpt.zip"
notarize "$stage/FlowGpt.zip" release/distribution/notarization-app.json
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
image="$project_dir/FlowGpt-$version-universal.dmg"
candidate_image="$stage/FlowGpt-$version-universal.dmg"
image_stage="$stage/image"
mkdir -p "$image_stage"
ditto "$app" "$image_stage/FlowGpt.app"
ln -s /Applications "$image_stage/Applications"
cp Docs/MAC_11.md "$image_stage/Read Me.md"
hdiutil create -volname "Install FlowGpt $version" -srcfolder "$image_stage" -format UDZO "$candidate_image"
codesign --force --sign "$FLOW_SIGNING_IDENTITY" "$candidate_image"
notarize "$candidate_image" release/distribution/notarization-dmg.json
xcrun stapler staple "$candidate_image"
xcrun stapler validate "$candidate_image"
spctl --assess --type open --context context:primary-signature --verbose=4 "$candidate_image"
hdiutil verify "$candidate_image"
# Replace the public artifact only after every verification succeeded.
mv -f "$candidate_image" "$image"
shasum -a 256 "${image:t}" > release/distribution/SHA256SUMS.txt
print "Notarized installer: $image"
