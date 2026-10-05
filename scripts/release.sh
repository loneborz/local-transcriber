#!/bin/bash
# Builds LocalTranscriber.app for release: Developer ID signed, notarized and stapled.
#
#   TEAM_ID=<team ID> NOTARY_PROFILE=<keychain profile> scripts/release.sh
#
# Needs a "Developer ID Application" certificate for TEAM_ID in the keychain and a
# notarytool profile stored with `xcrun notarytool store-credentials`. No credential
# lives in this repository. Raise CURRENT_PROJECT_VERSION before every submission
# (see the Engineering Reference). The result is $APP below.
set -euo pipefail
: "${TEAM_ID:?set TEAM_ID to your Apple Developer team ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile name}"

cd "$(dirname "$0")/.."
OUT="build/release"
APP="$OUT/LocalTranscriber.xcarchive/Products/Applications/LocalTranscriber.app"
ZIP="$OUT/LocalTranscriber.zip"

rm -rf "$OUT"
# archive, not build: a plain build adds get-task-allow, which notarization rejects.
# Hardened runtime is on in the Release configuration. The "Embed YouTube helper"
# phase signs the helper with the same identity, --options runtime and --timestamp.
# Apple Silicon only: the bundled helper is arm64.
xcodebuild -project LocalTranscriber.xcodeproj -scheme LocalTranscriber \
  -destination 'generic/platform=macOS' -configuration Release -derivedDataPath "$OUT" \
  -archivePath "$OUT/LocalTranscriber.xcarchive" ARCHS=arm64 \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp \
  archive
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose "$APP"
