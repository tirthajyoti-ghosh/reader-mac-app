# Reader — test suite

Run everything: `bash scripts/test.sh` (from the repo root).

## What runs

**Swift model tests** — `Tests/Swift/ModelTests.swift`, target `ReaderModelTests`
(host-less `bundle.unit-test`; compiles the self-contained `Theming.swift` /
`Theme.swift` directly, so it runs without launching the app).
`xcodebuild test -scheme ReaderModelTests -destination 'platform=macOS'`

- `Theming.parse` — themes.css → palettes, light/dark detection, `--accent` vs `--accent-emphasis`.
- `Theming.validateCustomTheme` (§8.5.1 security) — accepts token declarations; rejects `@import`
  and remote `url()`; drops `data:` url tokens; rejects token-less files.
- `Color(hexString:)`, `Palette.from` (accent override), `Theming.pairs` (sun/moon).
- `relativeTime`, `jsStringLiteral`.

**Renderer tests** — `tests/renderer.test.mjs` (jsdom + `node --test`). Loads the REAL
`app.js` + vendored markdown-it/highlight into a jsdom `reader.html` DOM.

- L0–2: headings, heading-ids, callouts, task lists, link classification (external/internal/anchor).
- Frontmatter → metadata block (never a giant H1); plain docs untouched.
- Find: all occurrences, cross-node, and **works with Bionic node-splits**; clears cleanly.
- Bionic never alters `textContent` (outline/links/scroll stay valid); fully reversible.
- Theming: `data-theme`, `data-reading` preset, token overrides set/clear on the root.
- A11y modes toggle `#doc` classes + line wrap/reverse.
- Export: `__docHTML` strips chrome + reading artifacts; `__buildExportCard` frames HTML at a width preset.

## Covered elsewhere (not in the automated suite)

These need a real layout/appearance engine or the full app, and are verified with the
Playwright browser harness + `cacheDisplay`/`takeSnapshot` snapshots during development:

- Line-focus **visual-line** splitting + the accent-soft band (needs `getClientRects`).
- Theme/preset **token retinting** of computed styles (needs a CSS engine).
- **Per-tab scroll preservation** across tab switches (native, multi-webview) — verified: open A,
  scroll, open B, return to A → scroll preserved.
- **Export capture fidelity** (fonts/Mermaid/KaTeX/colours in the PNG) and **cursor** behaviour.
