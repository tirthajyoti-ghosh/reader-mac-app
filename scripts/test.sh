#!/usr/bin/env bash
# Full test suite — all HEADLESS (no visible window, no focus theft):
#   1. Swift model logic       — XCTest, host-less
#   2. Renderer engine (WebKit)— off-screen WKWebView (same engine as the app / QL)
#   3. Renderer (jsdom)        — DOM logic in Node
#   4. Renderer (Chromium)     — Mermaid / KaTeX / theme tokens in headless Chromium
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export READER_TESTING=1   # any app-hosted test can't steal focus

echo "==> generate project"
xcodegen generate --quiet 2>/dev/null || xcodegen generate

echo "==> Swift model tests (XCTest, host-less)"
xcodebuild test -project "$ROOT/Reader.xcodeproj" -scheme ReaderModelTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet 2>/dev/null

echo "==> Renderer engine tests (off-screen WKWebView)"
xcodebuild test -project "$ROOT/Reader.xcodeproj" -scheme ReaderRenderTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet 2>/dev/null

echo "==> Renderer tests (jsdom + headless Chromium)"
(
  cd "$ROOT/tests"
  [ -d node_modules ] || npm install --silent
  # ensure the chromium binary exists for the headless browser test (idempotent)
  CHROME="$(node -e "process.stdout.write(require('playwright').chromium.executablePath())" 2>/dev/null || true)"
  [ -n "$CHROME" ] && [ -x "$CHROME" ] || npx playwright install chromium >/dev/null
  node --test
)

echo "==> ALL TESTS PASSED"
