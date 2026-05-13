#!/usr/bin/env bash
set -euo pipefail

# Builds bmad-manager.app and packages it as dist/bmad-manager.dmg.
# Run this on a Mac with Xcode (or Command Line Tools that include SwiftPM
# with multi-arch support) installed.

APP_NAME="bmad-manager"
DISPLAY_NAME="BMad Manager"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
STAGE_DIR="$BUILD_DIR/dmg-stage"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"

echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> Building release binary"
cd "$ROOT_DIR"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_PATH="$ROOT_DIR/.build/apple/Products/Release/$APP_NAME"
    echo "    Built universal binary (arm64 + x86_64)"
else
    echo "    Universal build unavailable; falling back to host arch"
    swift build -c release
    BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "ERROR: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling .app bundle"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc codesigning"
codesign --sign - --force --deep --options runtime "$APP_DIR"

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

echo ""
echo "Built $DMG_PATH"
echo "Share this single file with end users. They double-click it,"
echo "drag bmad-manager.app onto the Applications shortcut, and run it."
