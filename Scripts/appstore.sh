#!/bin/bash
# Archives the sandboxed App Store build.
#
#   DEVELOPMENT_TEAM=ABCDE12345 ./Scripts/appstore.sh
#
# Then upload the archive with Xcode's Organizer (Window > Organizer >
# Distribute App > App Store Connect), which handles the .pkg wrapping and
# authentication for you.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    echo "error: set DEVELOPMENT_TEAM to your 10-character Apple team ID."
    echo "       Find it at https://developer.apple.com/account under Membership."
    exit 1
fi

ARCHIVE="build/Stash.xcarchive"
rm -rf "$ARCHIVE"

echo "==> archiving for the App Store (sandboxed)"
xcodebuild archive \
    -project Stash.xcodeproj \
    -scheme Stash \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination 'generic/platform=macOS' \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Automatic

echo
echo "==> archived: $ARCHIVE"
echo "    Open Xcode > Window > Organizer, select this archive,"
echo "    then Distribute App > App Store Connect > Upload."
