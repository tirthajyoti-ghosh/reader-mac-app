#!/usr/bin/env bash
# Regenerate Reader.icns from the source SVG (design/icon/icon-dark.svg).
# Requires rsvg-convert (`brew install librsvg`) + iconutil (built in).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/design/icon/icon-dark.svg"
SET="$ROOT/scripts/.iconset-tmp/Reader.iconset"
rm -rf "$ROOT/scripts/.iconset-tmp"; mkdir -p "$SET"

render() { rsvg-convert -w "$1" -h "$1" "$SRC" -o "$SET/$2"; }
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$SET" -o "$ROOT/Reader.icns"
rm -rf "$ROOT/scripts/.iconset-tmp"
echo "wrote $ROOT/Reader.icns ($(stat -f%z "$ROOT/Reader.icns") bytes)"
