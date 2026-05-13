#!/usr/bin/env bash
set -euo pipefail

# Generates Resources/AppIcon.icns from Resources/icon-source.png using
# macOS-built-in sips + iconutil (no Homebrew required).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="$ROOT_DIR/Resources/icon-source.png"
ICONSET="$ROOT_DIR/Resources/AppIcon.iconset"
OUT="$ROOT_DIR/Resources/AppIcon.icns"

if [ ! -f "$SRC" ]; then
    echo "ERROR: missing $SRC" >&2
    exit 1
fi
if ! command -v sips >/dev/null || ! command -v iconutil >/dev/null; then
    echo "ERROR: this script requires macOS (sips + iconutil)." >&2
    exit 1
fi

rm -rf "$ICONSET" "$OUT"
mkdir -p "$ICONSET"

# Apple's required sizes: 16, 32, 128, 256, 512 @ 1x and 2x.
for entry in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    size="${entry%% *}"
    name="${entry##* }"
    sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
