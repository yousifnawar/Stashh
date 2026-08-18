#!/bin/bash
# Builds Stash.app into ./build/Stash.app
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

# UNIVERSAL=1 produces a binary that runs on both Apple Silicon and Intel.
# Spelled out rather than using an array: bash 3.2 (what ships with macOS)
# treats an empty array as unbound under `set -u`.
echo "==> swift build ($CONFIG)"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "==> universal (arm64 + x86_64)"
    swift build -c "$CONFIG" --arch arm64 --arch x86_64
    BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/Stash"
else
    swift build -c "$CONFIG"
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/Stash"
fi
APP="build/Stash.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stash"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign with a stable identifier so macOS remembers granted permissions.
codesign --force --deep --sign - --identifier com.nawar.stash "$APP" >/dev/null 2>&1 || true

echo "==> built $APP"
