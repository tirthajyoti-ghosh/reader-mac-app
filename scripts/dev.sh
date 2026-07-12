#!/usr/bin/env bash
# Build + install + run the STAGING app ("Reader Canary") — the everyday dev loop.
# Staging has its own bundle id / name / icon, installs to ~/Applications, and never
# touches the production Reader.app in /Applications. Usage:
#   scripts/dev.sh                 # build, install to ~/Applications, launch
#   scripts/dev.sh path/to/file.md # ...and open that file
#   READER_TESTING=1 scripts/dev.sh # launch without stealing focus (no activate)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="$ROOT/build.noindex"   # .noindex → Spotlight won't index build products as dupe apps
APP_NAME="Reader Canary.app"
BUILT="$DERIVED/Build/Products/Staging/$APP_NAME"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME"

echo "▸ xcodegen generate"
xcodegen generate --quiet

echo "▸ build (Staging)"
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Staging \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=YES build -quiet

echo "▸ install → $DEST"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

if [ "${READER_TESTING:-}" = "1" ]; then
  # Automated run: launch the binary directly with the env var so the focus-guard
  # in AppDelegate skips NSApp.activate / orderFront (no focus theft).
  echo "▸ launch (READER_TESTING=1, no focus steal)"
  READER_TESTING=1 "$DEST/Contents/MacOS/Reader Canary" "$@" &
elif [ $# -gt 0 ]; then
  echo "▸ open $*"
  open -a "$DEST" "$@"
else
  echo "▸ open"
  open "$DEST"
fi
