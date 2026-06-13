#!/usr/bin/env bash
set -euo pipefail

# Installs the built DMG into /Applications.
#
# Mounts dist/bmad-manager.dmg (the output of scripts/build_release.sh),
# copies the .app out with `ditto`, and detaches — discovering the volume
# mount point and the .app name dynamically rather than hard-coding them.
#
# Usage:
#   scripts/install.sh                  installs dist/bmad-manager.dmg
#   scripts/install.sh path/to/Some.dmg installs a specific DMG

BUNDLE_NAME="bmad-manager"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_PATH="${1:-$ROOT_DIR/dist/${BUNDLE_NAME}.dmg}"

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH" >&2
    echo "Build it first: scripts/build_release.sh" >&2
    exit 1
fi

echo "==> Mounting $DMG_PATH"
# hdiutil prints tab-separated columns; the mount line is the one with
# /Volumes/, and its last field is the mount point (kept whole so volume
# names containing spaces survive).
MNT="$(hdiutil attach -nobrowse "$DMG_PATH" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
if [ -z "$MNT" ]; then
    echo "ERROR: could not determine the DMG mount point" >&2
    exit 1
fi

# Always detach, even if a later step fails.
cleanup() { hdiutil detach "$MNT" >/dev/null 2>&1 || true; }
trap cleanup EXIT

APP_SRC="$(find "$MNT" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP_SRC" ]; then
    echo "ERROR: no .app found inside the DMG" >&2
    exit 1
fi
APP_NAME="$(basename "$APP_SRC")"
APP_DEST="/Applications/$APP_NAME"

echo "==> Found $APP_NAME"

# Quit a running instance so the replacement isn't a stale copy. Best-effort.
osascript -e "quit app \"${APP_NAME%.app}\"" >/dev/null 2>&1 || true

echo "==> Installing to $APP_DEST"
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"

# A locally built ad-hoc DMG isn't quarantined, but strip it anyway in case
# this was run on a downloaded copy, so the first launch is clean.
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

echo ""
echo "Installed $APP_NAME → /Applications"
echo "Launch it:  open \"$APP_DEST\""
