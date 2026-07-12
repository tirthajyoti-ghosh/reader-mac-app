#!/usr/bin/env bash
# Regenerate the app .icns files from the source SVGs.
#   scripts/make-icon.sh            → Reader.icns          (production, design/icon/icon-dark.svg)
#   scripts/make-icon.sh staging    → Reader-Staging.icns  (staging,    design/icon/icon-staging.svg)
# Requires rsvg-convert (`brew install librsvg`) + iconutil (built in).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-production}" in
  staging) SRC="$ROOT/design/icon/icon-staging.svg"; OUT="$ROOT/Reader-Staging.icns"; NAME="Reader-Staging" ;;
  *)       SRC="$ROOT/design/icon/icon-dark.svg";    OUT="$ROOT/Reader.icns";         NAME="Reader" ;;
esac

SET="$ROOT/scripts/.iconset-tmp/$NAME.iconset"
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

iconutil -c icns "$SET" -o "$OUT"
rm -rf "$ROOT/scripts/.iconset-tmp"
echo "wrote $OUT ($(stat -f%z "$OUT") bytes)"
