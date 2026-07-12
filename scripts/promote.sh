#!/usr/bin/env bash
# Promote confirmed changes to PRODUCTION: build the Release identity and install
# it to /Applications/Reader.app. This is the ONLY path that touches production —
# run it only after the change is verified on staging (scripts/dev.sh + test.sh).
#   scripts/promote.sh          # prompts before replacing /Applications/Reader.app
#   scripts/promote.sh --yes    # skip the confirmation
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="$ROOT/build.noindex"   # .noindex → Spotlight won't index build products as dupe apps
APP_NAME="Reader.app"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

if [ "${1:-}" != "--yes" ]; then
  read -r -p "Promote to production — replace $DEST ? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "aborted"; exit 1; }
fi

echo "▸ xcodegen generate"
xcodegen generate --quiet

echo "▸ build (Release)"
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=YES build -quiet

echo "▸ install → $DEST"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

# Re-register so Launch Services picks up the fresh build; re-assert prod as the
# default .md handler (never done for staging).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" || true
if command -v duti >/dev/null 2>&1; then
  duti -s com.tirthajyoti.Reader net.daringfireball.markdown all || true
fi

echo "✓ promoted to $DEST"
