#!/usr/bin/env bash
# Full test suite: Swift model logic (XCTest, host-less) + renderer (jsdom).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "==> Swift model tests (XCTest)"
xcodebuild test -project "$ROOT/Reader.xcodeproj" -scheme ReaderModelTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet
echo "==> Renderer tests (jsdom)"
( cd "$ROOT/tests" && [ -d node_modules ] || npm install --silent; node --test )
echo "==> ALL TESTS PASSED"
