#!/bin/bash
# Packages the release app built by scripts/release.sh into a signed, notarized and
# stapled DMG. It never rebuilds the app: it packages the exact app at $APP.
#
#   TEAM_ID=<team ID> NOTARY_PROFILE=<keychain profile> scripts/dmg.sh
#
# Same credentials as release.sh; none live in this repository. The DMG holds only
# "Local Transcriber.app" and an Applications shortcut. Apple Silicon only.
# Results: build/dist/LocalTranscriber-<version>.dmg and its .sha256 file.
set -euo pipefail
: "${TEAM_ID:?set TEAM_ID to your Apple Developer team ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile name}"

cd "$(dirname "$0")/.."
APP="build/release/LocalTranscriber.xcarchive/Products/Applications/LocalTranscriber.app"
fail() { echo "error: $*" >&2; exit 1; }

# The app must be the finished, stapled release app.
[ -d "$APP" ] || fail "$APP is missing; run scripts/release.sh first"
for bin in "$APP/Contents/MacOS/LocalTranscriber" "$APP/Contents/Helpers/python3.13"; do
  [ "$(lipo -archs "$bin")" = arm64 ] || fail "$bin is not arm64 only"
done
codesign --verify --deep --strict "$APP" || fail "app signature is invalid"
xcrun stapler validate "$APP" >/dev/null || fail "app has no valid stapled ticket"
spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the app"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
OUT="build/dist"
DMG="$OUT/LocalTranscriber-$VERSION.dmg"
echo "Packaging LocalTranscriber $VERSION ($BUILD)"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Local Transcriber.app"
ln -s /Applications "$STAGE/Applications"
[ "$(ls -A "$STAGE" | tr '\n' '|')" = "Applications|Local Transcriber.app|" ] || fail "unexpected staging contents"
[ -z "$(find "$STAGE/" \( -name .DS_Store -o -name __pycache__ \))" ] || fail ".DS_Store or __pycache__ in app"

mkdir -p "$OUT"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Local Transcriber" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' "/Developer ID Application: .*\\($TEAM_ID\\)/{print \$2; exit}")
[ -n "$IDENTITY" ] || fail "no Developer ID Application identity for team $TEAM_ID"
codesign --sign "$IDENTITY" --timestamp --verbose "$DMG"

RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
echo "$RESULT"
[ "$(plutil -extract status raw - <<<"$RESULT")" = Accepted ] || fail "notarization was not Accepted"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" && shasum -a 256 -c "$(basename "$DMG").sha256")
echo "Done: $DMG"
