#!/bin/bash
# Packages Stash.app into a distributable DMG.
#
#   ./Scripts/package.sh                          → ad-hoc signed DMG (Gatekeeper will warn)
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./Scripts/package.sh
#   ...plus NOTARY_PROFILE=stash-notary           → also notarised and stapled
#
# Create the notary profile once with:
#   xcrun notarytool store-credentials stash-notary \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
APP="build/Stash.app"
STAGE="build/dmg"
DMG="build/Stash-$VERSION.dmg"

./Scripts/build.sh release

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "==> signing with: $DEVELOPER_ID"
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID" --identifier com.nawar.stash "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
else
    echo "==> no DEVELOPER_ID set — keeping the ad-hoc signature"
    echo "    (on first launch users must allow it in"
    echo "     System Settings > Privacy & Security > Open Anyway)"
fi

echo "==> staging disk image"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Stash" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --sign "$DEVELOPER_ID" "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> submitting to Apple for notarisation (this takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo "==> notarised and stapled"
fi

echo "==> $DMG  ($(du -h "$DMG" | cut -f1))"
