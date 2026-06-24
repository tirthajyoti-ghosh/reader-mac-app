# Reader

A calm, **read-only** Markdown viewer for macOS, plus a Quick Look preview
extension that **shares the exact same renderer** — so an open tab and Finder's
spacebar preview look identical. Styled to Claude Desktop's reading aesthetic:
warm near-black canvas, Source Sans 3 reading face, a single clay accent, and a
quiet reading-progress hairline.

> Think *"Preview.app for Markdown, with Claude Desktop's reading aesthetic."*

![Reader — dark](handover-reference) <!-- see comps/images in the design handover -->

## Features

- **Reads beautifully** — Source Sans 3 body + headings, JetBrains Mono code,
  the exact extracted Claude-Desktop color tokens, light + dark.
- **Full Markdown** — GFM tables, task lists, strikethrough, autolinks; fenced
  code with syntax highlighting; blockquotes; GitHub **callouts**
  (`[!NOTE]` / `[!TIP]` / `[!IMPORTANT]` / `[!WARNING]` / `[!CAUTION]`);
  **Mermaid** diagrams; **KaTeX** math (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`).
- **Link surface** — a link is a *detour, not a destination*, so reading position is
  sacred. **Hover** a link for a peek card (live preview; offline fallback in Quick Look);
  **click** an external link for a slide-over **sheet** that dims the doc but never scrolls
  it (Esc / tap-scrim returns to the exact spot); **drag the sheet wider** or **⌥-click** to
  escalate to a **split**; **⌘-click / right-click** opens the system browser; internal
  `.md` links navigate **in place** with a breadcrumb **Back** that restores the prior doc
  *and* its scroll; `#anchor`s smooth-scroll + briefly flash the target heading.
- **Default `.md` handler** — double-click a Markdown file to open it rendered.
- **Quick Look** — spacebar a `.md` in Finder for an identical, chrome-less preview.
- **Tabs**, a **sidebar** that lists `.md/.markdown/.txt` in a watched folder
  (default `~/.claude/plans`) with a folder picker + refresh, **live-reload**
  (edits to an open file re-render instantly, including atomic “replace on save”),
  **⌘F find** with wrap-around + match count, and a light/dark toggle.
- **Fully offline** — every JS lib (markdown-it, highlight.js, Mermaid, KaTeX) and
  every font (incl. KaTeX's math fonts) is bundled locally. Nothing hits the network;
  the sandboxed Quick Look extension renders math and diagrams with no connectivity.

## Architecture

A SwiftUI shell draws the native chrome (sidebar, tabs, toolbar, find bar) and
hosts a `WKWebView` that loads one bundled **`WebResources/reader.html`**. Swift
never builds HTML — it injects the raw Markdown via `window.__render(text)` and
flips the palette via `window.__setTheme('dark'|'light')`. The Quick Look
extension loads the **same** `reader.html`, so both surfaces render from the same
CSS/JS. `design-tokens.css` (copied verbatim from the design handover) is the
single source of truth for the document surface; the native chrome mirrors the
same token values.

```
App/            SwiftUI app — ReaderApp, AppModel, ContentView, Sidebar, TabBar,
                FindBar, EmptyState, MarkdownWebView, FileWatcher, Document, Theme
QuickLook/      QLPreviewingController + Info.plist + entitlements (.appex)
WebResources/   reader.html, app.js, design-tokens.css, hljs-tokens.css,
                vendor/ (libs), fonts/ (woff2)   ← folder reference in BOTH targets
scripts/        vendor.sh — fetches + lays out the libs and fonts
project.yml     XcodeGen project (no hand-edited .xcodeproj)
samples/        kitchen-sink.md for testing
```

## Build

Requires **macOS 14+** and **Xcode 15+**.

```sh
# 1. tooling
brew install xcodegen

# 2. vendor the JS libs + woff2 fonts into WebResources/ (already committed,
#    re-run only to refresh)
bash scripts/vendor.sh

# 3. generate the Xcode project and build
xcodegen generate
open Reader.xcodeproj        # ⌘R to run
# …or headless:
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build
```

The build ad-hoc-signs locally (no Apple Developer team required).

## Make Reader the default Markdown app

- **Finder:** right-click any `.md` → *Get Info* → *Open with* → **Reader** →
  *Change All…*
- **CLI** (if you have [`duti`](https://github.com/moretension/duti)):
  ```sh
  duti -s com.tirthajyoti.Reader net.daringfireball.markdown all
  ```

## Enable / test Quick Look

The preview extension is embedded in the app, so it registers when macOS first
sees `Reader.app` (run it once, or register explicitly):

```sh
# register the app (and its appex) with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /path/to/Reader.app

# confirm the extension is known to the system
pluginkit -mi com.tirthajyoti.Reader.QuickLook

# reset the Quick Look cache, then preview a file
qlmanage -r
qlmanage -p ~/.claude/plans/some-file.md
```

Then select a `.md` in Finder and press **space**.

## Fonts — swap or license

The reading face (body + headings) is **Source Sans 3** and code is **JetBrains
Mono** — both OFL, bundled as `woff2` in `WebResources/fonts/` (the sans ships
weights 400/600/700 + 400 italic) and declared via `@font-face` in `reader.html`.
To swap the reading face, drop new `woff2` files in `fonts/`, update the
`@font-face` blocks, and change `--font` in `design-tokens.css`. The pinned font
packages live in `scripts/vendor.sh`.

## Sandboxing

The **app is non-sandboxed** (personal use) so it can watch `~/.claude/plans` and
open files from anywhere — and, because it isn't sandboxed, it can make the
**outbound network requests** the link surface needs (resolving Open Graph metadata
for hover peeks and loading external pages in the sheet/split). Those fetches run
**only on user hover/click**, through an **ephemeral** (non-persistent) session.
The **Quick Look extension is sandboxed** (a system requirement) with
`com.apple.security.files.user-selected.read-only` (+ `network.client`, which
WKWebView needs to render even local content); there, links are styled but
**non-interactive** — no peek/sheet/fetch, just the offline fallback.

To ship a **sandboxed, notarized** build instead: enable App Sandbox on the app,
persist the watched folder via a **security-scoped bookmark** (the folder picker
already uses `NSOpenPanel`, which grants access), turn on the **Hardened Runtime**,
and sign + notarize with a Developer ID.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Double-click doesn't open in Reader | `lsregister -f Reader.app`, then *Get Info → Open with → Change All* |
| Spacebar preview is blank / stale | `qlmanage -r && qlmanage -r cache`, then re-preview; `qlmanage -p file.md` prints diagnostics |
| QL extension not listed | `pluginkit -mi com.tirthajyoti.Reader.QuickLook`; run `Reader.app` once to register |
| Fonts/diagrams missing | re-run `bash scripts/vendor.sh`, confirm `WebResources/vendor` + `fonts` are populated, regenerate |

## License

Code: do as you like. Bundled fonts are OFL (Source Sans 3, JetBrains Mono);
bundled libraries keep their own licenses (markdown-it, highlight.js — MIT;
Mermaid — MIT; KaTeX — MIT).
