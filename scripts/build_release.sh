#!/usr/bin/env bash
set -euo pipefail

# Builds bmad-manager.app and packages it as dist/bmad-manager.dmg.
# Run this on a Mac with Xcode (or Command Line Tools that include SwiftPM
# with multi-arch support) installed.
#
# Optional environment variables for signed + notarized releases:
#   APPLE_DEVELOPER_ID   "Developer ID Application: Your Name (TEAMID)"
#                        When set, replaces ad-hoc codesigning with a real
#                        Developer ID signature (hardened runtime + timestamp).
#   NOTARY_PROFILE       keychain profile name created with
#                        `xcrun notarytool store-credentials`. When set
#                        together with APPLE_DEVELOPER_ID, the DMG is
#                        notarized and stapled, eliminating the Gatekeeper
#                        warning for end users.
#
# If neither is set, the script falls back to ad-hoc signing (end users
# need to right-click → Open on first launch — fine for personal use).

BUNDLE_NAME="bmad-manager"      # the .app / .dmg filename (user-facing)
TARGET_NAME="BmadManager"       # the SwiftPM target / Mach-O binary name
DISPLAY_NAME="BMad Manager"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/${BUNDLE_NAME}.app"
STAGE_DIR="$BUILD_DIR/dmg-stage"
DMG_PATH="$DIST_DIR/${BUNDLE_NAME}.dmg"

echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> Building release binary"
cd "$ROOT_DIR"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_PATH="$ROOT_DIR/.build/apple/Products/Release/$TARGET_NAME"
    echo "    Built universal binary (arm64 + x86_64)"
else
    echo "    Universal build unavailable; falling back to host arch"
    swift build -c release
    BIN_PATH="$ROOT_DIR/.build/release/$TARGET_NAME"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "ERROR: built binary not found at $BIN_PATH" >&2
    exit 1
fi

if [ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ] && [ -f "$ROOT_DIR/Resources/icon-source.png" ]; then
    echo "==> Generating AppIcon.icns from icon-source.png"
    "$SCRIPT_DIR/make_icon.sh"
fi

echo "==> Assembling .app bundle"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$TARGET_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$TARGET_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [ -n "${APPLE_DEVELOPER_ID:-}" ]; then
    echo "==> Codesigning with Developer ID"
    codesign --sign "$APPLE_DEVELOPER_ID" \
        --force --deep --options runtime --timestamp \
        "$APP_DIR"
else
    echo "==> Ad-hoc codesigning (set APPLE_DEVELOPER_ID for a Developer ID signature)"
    codesign --sign - --force --deep --options runtime "$APP_DIR"
fi

echo "==> Staging DMG contents"
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

if [ -n "${APPLE_DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Submitting DMG to Apple notary service (this can take a few minutes)"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "==> Stapling notarization ticket to DMG"
    xcrun stapler staple "$DMG_PATH"
    NOTARIZED=1
else
    NOTARIZED=0
fi

echo ""
echo "Built $DMG_PATH"
if [ "$NOTARIZED" = 1 ]; then
    echo "Notarized and stapled — end users can just double-click to open."
else
    echo "Share this single file with end users. They double-click it,"
    echo "drag bmad-manager.app onto the Applications shortcut, and run it."
    if [ -z "${APPLE_DEVELOPER_ID:-}" ]; then
        echo "First launch requires right-click → Open (ad-hoc signature, no notarization)."
    fi
fi
