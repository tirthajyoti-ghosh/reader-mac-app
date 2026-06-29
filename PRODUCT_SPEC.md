# Reader — Product Specification

> Working title: **Reader** (preferred direction: **Margin**). A calm, private, native macOS app for reading markdown — especially the output AI tools produce — that is yours and lives on your machine.

| Field | Value |
|---|---|
| Document status | **Draft v1.0 — for sign-off** |
| Date | 2026-06-28 |
| Owner | Tirtha |
| Platform | macOS 14+ (Apple Silicon + Intel) |
| License / model | Open source, free |
| Supersedes | All prior ad-hoc decisions in design/build threads |

---

## 0. How to read this document

This spec is organized **foundation-up**. Section 6 (Architecture) and Section 7 (**The Token Contract**) are the backbone — the load-bearing wall everything else stands on. Sections 8.x specify features in strict dependency order by layer (0 → 5). Nothing in a higher layer may violate the **Invariants** (Section 5) or bypass the Token Contract (Section 7).

Sign-off (Section 13) is a commitment to: the Invariants, the Token Contract, the Layer 0–3 scope as **1.0**, and the acceptance criteria therein.

---

## 1. Summary

Reader renders markdown into a calm, beautiful, read-only document and makes that experience available both as a standalone app (double-click a `.md`) and in Finder's Quick Look (spacebar) — using a **single shared renderer** so both look identical. It is local-first, private, free, and open source.

The product is built on one technical idea: **every visual property flows from a single, complete set of design tokens (the Token Contract).** Because of that, the features that differentiate Reader — full theming, an accessibility/focus reading mode, and beautiful sharing — are cheap to build and impossible to get wrong, rather than expensive refactors.

**Positioning:** *"A calm, private place to read what AI gives you — and it's yours."*

---

## 2. Vision & problem

People increasingly read markdown they didn't write: AI output (Claude Code plans, research/findings docs, ChatGPT/Claude/Gemini answers exported as `.md`), READMEs, specs, and documentation. The reading experience for this content is poor — either a raw-syntax text file, a heavyweight editor, or a generic preview that nobody tuned for *reading*. The specific look-and-feel that reads best (Claude Desktop's reading surface) isn't available in any viewer, which is the origin of this product.

Reader treats reading as the product: typography, calm, privacy, and the ability to make the surface *yours*.

---

## 3. Target users

The same core asset (a calm, local, beautiful markdown reading surface) serves four audiences. The product is positioned for all four without becoming four products.

1. **Developers reading AI/agent output** — the origin user. Reads Claude Code plans and research docs; wants live-reload, Quick Look, and fidelity.
2. **Anyone reading/keeping AI output** (largest, mostly non-developer) — exports AI conversations as `.md` and wants them readable, not raw.
3. **Read-it-later / own-your-data readers** — value local-first, private, open-source reading after cloud reading apps proved fragile.
4. **Accessibility & focus readers (ADHD, dyslexia)** — need dyslexia fonts, line focus, spacing controls, bionic mode, TTS. Highest gratitude-per-effort; mostly cheap CSS.

---

## 4. Goals & Non-Goals

### 4.1 Goals
- Be the most pleasant way to **read** markdown on macOS.
- Render app and Quick Look **identically**, fully **offline**.
- Make the reading surface fully **themeable** and **personalizable** with zero code required.
- Stay **small, fast, native, calm, private, free, open source**.

### 4.2 Non-Goals (explicit — protects focus)
- **Not an editor.** No writing/editing surface. (Editing is out of scope for all layers in this spec.)
- **No accounts, no cloud, no sync server, no telemetry.**
- **Not a knowledge base** (no graph view, no backlinks engine).
- **Not a feature-maximalist app.** Every feature must justify itself against "calm" and "small/focused."
- **No AI features inside the app** in 1.0 (the app reads AI *output*; it does not call models).

---

## 5. Product Invariants (govern every layer; never violated)

| # | Invariant | Meaning |
|---|---|---|
| I1 | **Local & offline-first** | Core reading works with no network. The *only* permitted network call is opt-in link previews (Section 8.2.4). |
| I2 | **Private** | No telemetry, analytics, accounts, or background phone-home. |
| I3 | **Free & open source** | Source public; no paywall in 1.0 scope. |
| I4 | **Calm** | Every non-core feature is **toggle-off**. The reading surface is never cluttered by default. |
| I5 | **One renderer** | App window and Quick Look use the *same* render core and Token Contract. Output is visually identical. |
| I6 | **Scroll position is sacred** | Reading position is preserved across link open/close, in-place navigation + Back, live-reload, and theme changes. |
| I7 | **Token-driven** | No visual property is hardcoded outside the Token Contract (Section 7). |

---

## 6. Architecture

### 6.1 Stack
- **Native macOS**, Swift + SwiftUI shell.
- Rendering via **WKWebView** loading a bundled, fully-vendored HTML/CSS/JS render core (`reader.html`).
- Project generated with **XcodeGen** (`project.yml`); no hand-edited `.xcodeproj`.
- Two targets: the **app** and an embedded **Quick Look Preview Extension** sharing the same `WebResources` (renderer + vendored libs + bundled fonts) via folder reference.
- App runs **non-sandboxed** for personal/local use (full file access); a sandboxed/notarized distribution path (security-scoped bookmarks, hardened runtime, network entitlement for previews) is documented for later. Quick Look extension is sandboxed by the system.

### 6.2 The layered model (dependency order)

```
Layer 5  Ecosystem & Longevity      (community theme gallery, cross-platform)
Layer 4  Keep & Broaden             (AI-export reading, highlights, TTS)
Layer 3  Identity & Reach           (theming, accessibility/focus, sharing)   ── 1.0 ships through here
Layer 2  Reading Surface            (progress hairline, find, outline, links)
Layer 1  Shell                      (WKWebView host, QL ext, tabs, sidebar, live-reload)
Layer 0  Backbone                   (render core + THE TOKEN CONTRACT)
```

Each layer is the ground the next stands on. Layer 3 is a near-pure function of Layer 0: theming = swap the token block; accessibility = expose token controls + small text transforms; sharing = render the tokenized DOM to an image.

### 6.3 The one rule
**No visual property — color, font, size, spacing, width, radius — is hardcoded anywhere outside the Token Contract.** This is the single most important engineering constraint in the product.

---

## 7. The Token Contract (the backbone)

The canonical, complete set of CSS custom properties. Everything visual reads from these. Colors are the **exact tokens extracted from Claude Desktop**. The contract has three groups: **Color**, **Type**, **Reading ergonomics**.

> Borders: Claude paints borders as the contrast color at ~8–10% opacity. The solid hexes below are the practical equivalent; an alternate `hsl(0 0% 100% / .08)` (dark) / `hsl(0 0% 0% / .08)` (light) is acceptable for a subtler line.

### 7.1 Color tokens

| Token | Dark | Light | Role |
|---|---|---|---|
| `--bg` | `#1F1F1E` | `#F8F8F6` | App / reading background |
| `--surface` | `#2C2C2B` | `#FFFFFF` | Sidebar, cards, sheet, hover, raised panels |
| `--code-bg` | `#171716` | `#EFEEEB` | Code blocks (recessed) |
| `--text` | `#F8F8F6` | `#121212` | Primary text |
| `--text-secondary` | `#C3C2B7` | `#373734` | Secondary text |
| `--text-muted` | `#97958C` | `#7B7974` | Captions, list markers, metadata |
| `--border` | `#454442` | `#E7E6E1` | Hairlines, dividers |
| `--accent` | `#D97757` | `#C6613F` | Clay — links, focus, active, progress hairline |
| `--accent-emphasis` | `#C6613F` | `#B6532F` | Hover/pressed accent |

#### Syntax tokens

| Token | Dark | Light |
|---|---|---|
| `--syntax-keyword` | `#D97757` | `#B6532F` |
| `--syntax-string` | `#B5C89A` | `#5C7042` |
| `--syntax-number` | `#D9A05B` | `#9A6A1F` |
| `--syntax-comment` | `#6F6D65` | `#9B998F` |
| `--syntax-function` | `#C9A8E8` | `#7A4BA8` |
| `--syntax-variable` | `#E8E6DC` | `#2B2A27` |

### 7.2 Type tokens

| Token | Default | Notes |
|---|---|---|
| `--font` | `"Source Serif 4", Georgia, "Times New Roman", Times, serif` | Reading face. Source Serif 4 (OFL) **bundled** as woff2 — closest free stand-in for Claude's licensed "Anthropic Serif." |
| `--mono` | `"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace` | Code face. JetBrains Mono (OFL) **bundled**. |
| `--ui-font` | `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` | App chrome only (sidebar/tabs/toolbar). Never used in the reading surface. |
| `--fs-base` | `17px` | Body size |
| `--fs-h1`…`--fs-h4` | `1.85 / 1.4 / 1.15 / 1.0` em | Heading scale |
| `--fw-normal` / `--fw-semibold` | `400 / 650` | Weights |

> **Licensing hook:** "Anthropic Serif", Tiempos, Galaxie Copernicus, and Styrene B are commercial and MUST NOT be bundled. If a user licenses one, they drop its woff2 into `/fonts` and prepend its name to `--font`.

### 7.3 Reading-ergonomics tokens

The part most apps hardcode — and the reason the contract is the backbone, because the accessibility/focus features (Section 8.3.2) are just these tokens made user-adjustable.

| Token | Default | Role |
|---|---|---|
| `--measure` | `46rem` | Reading column max width |
| `--leading` | `1.72` | Body line-height |
| `--para-space` | `1.05em` | Paragraph spacing |
| `--letter-spacing` | `0` | Tracking |
| `--word-spacing` | `0` | Word spacing |
| `--heading-leading` | `1.25` | Heading line-height |
| `--radius` / `--radius-lg` | `8px / 12px` | Corner radii |

---

## 8. Feature specification (by layer)

### 8.0 Layer 0 — Backbone: Render Core + Token Contract

**8.0.1 Render core.** Markdown → semantic HTML, fully vendored/offline.
- Supports: GFM (tables, task lists, strikethrough, autolinks), fenced code with syntax highlighting, blockquotes, **callouts** (`[!NOTE]/[!TIP]/[!WARNING]/[!IMPORTANT]/[!CAUTION]` → tinted cards with uppercase title), inline code, **Mermaid** diagrams, **KaTeX** math (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`), horizontal rules, **heading anchors/IDs**.
- API surface: `window.__render(markdown)`, `window.__setTheme('dark'|'light')`. No other entry points.
- Acceptance:
  - [ ] All listed elements render correctly from a kitchen-sink document.
  - [ ] Renders with **no network access** (verified by running offline).
  - [ ] Every heading has a stable slug ID.
  - [ ] Mermaid + KaTeX render from **local** assets (work inside the sandboxed Quick Look extension).

**8.0.2 Token Contract.** Implement Section 7 as the single source of truth.
- Acceptance:
  - [ ] Every token in Section 7 exists with the specified default for both themes.
  - [ ] **Audit passes: zero hardcoded visual values** (color/font/size/spacing/width/radius) outside the contract in `reader.html`/CSS.
  - [ ] Switching the token block is the *only* change required to retheme; no other CSS edits needed.

> **First implementation action:** harden the contract — convert every stray hardcoded value (e.g. `46rem`, `1.72`, `17px`) into a token. No higher-layer work begins until 8.0.2 acceptance passes.

---

### 8.1 Layer 1 — Shell

**8.1.1 WKWebView host + Quick Look extension** sharing one renderer (I5).
- Acceptance: [ ] App and Quick Look render the same file identically. [ ] Quick Look awaits load+render before snapshot (no blank previews).

**8.1.2 Document model & tabs** — open files; multiple open docs as selectable, closable tabs.
- Acceptance: [ ] Tabs open/close/switch; closing a tab returns focus correctly; per-tab state isolated.

**8.1.3 Sidebar** — lists `.md/.markdown/.txt` in a watched folder (default `~/.claude/plans`); folder-name header, folder picker (NSOpenPanel), refresh; click → open in tab.
- Acceptance: [ ] Lists and opens files; folder picker changes the watched folder; empty folder shows an empty state.

**8.1.4 Default `.md` handler** — register via imported `net.daringfireball.markdown` UTI (extensions `md/markdown/mdown/mkd`); markdown = LSHandlerRank Default, plain-text = Alternate, role Viewer; catch opens via `application(_:open:)`.
- Acceptance: [ ] Double-clicking a `.md` in Finder opens it rendered in Reader.

**8.1.5 Live-reload** — kqueue `DispatchSourceFileSystemObject` per open file; re-render on `.write/.extend/.rename/.delete`; **re-arm after atomic saves**; **preserve scroll** (I6).
- Acceptance: [ ] Editing a watched file updates the open tab live. [ ] Atomic-save editors still trigger updates. [ ] Scroll position is retained across reload.

**8.1.6 ⌘O open** via NSOpenPanel.

---

### 8.2 Layer 2 — Reading Surface

**8.2.1 Reading-progress hairline (signature)** — a thin `--accent` line at the top of the doc that fills with scroll.
- Acceptance: [ ] Fills 0→100% with scroll; quiet; uses `--accent`.

**8.2.2 ⌘F find** — find bar driving `WKWebView.find(_:configuration:)` with wrap-around.
- Acceptance: [ ] Finds + cycles matches; Esc closes; wraps.

**8.2.3 Outline / TOC panel** — nested headings (H1–H6) extracted from the rendered DOM; click-to-jump (smooth scroll, no reload); scroll-spy active heading; live filter; toggle via toolbar button + shortcut (⌥⌘O or ⌘\); right-side placement; per-tab; coexists with sheet/split (no overlap); empty state ("No headings").
- Acceptance: [ ] Lists all headings nested; click jumps without reload/scroll-loss; active heading tracks scroll; filter narrows live; toggle persists, defaults closed; refreshes on live-reload; doesn't collide with the link sheet/split or the file sidebar.

**8.2.4 Link experience** — *a link is a detour, not a destination; scroll is sacred (I6).* Intercept activation via `WKNavigationDelegate decidePolicyFor`, cancel default in-webview navigation, and route by type; the doc webview stays **mounted** (never reloaded).
- **Default (external URL)** → **slide-over sheet**: a second WKWebView over the dimmed doc; Esc/tap-scrim returns to exact scroll; sheet has its own header (title/domain, back/forward within sheet, open-in-split, open-in-browser, close); non-persistent data store.
- **Hover peek** (debounced) → posts href to Swift; external → fetch + parse OG/meta (title, site, description, image, favicon); internal `.md` → rendered snippet; card actions (open / split / browser); session-cached; fetch only on user hover/click; **offline fallback** = link text + domain.
- **Escalate to split** by dragging the sheet wider past threshold, or ⌥-click.
- **System browser** via ⌘-click / right-click → `NSWorkspace.open`; right-click menu names all options.
- **Internal `.md`** → load via the reader pipeline **in place**; per-tab back stack; quiet breadcrumb ("← Source doc"); **Back restores prior doc + scrollTop**.
- **`#anchor`** → smooth-scroll + briefly highlight heading; no sheet/nav.
- **localhost / 127.0.0.1** → open in a new tab (interactive local app).
- Acceptance: [ ] Hover shows a peek (live in app; offline fallback in Quick Look). [ ] Click opens a sheet with the doc preserved + dimmed; Esc returns to exact scroll. [ ] Drag-wider / ⌥-click → split; ⌘/right-click → browser. [ ] Internal `.md` navigates in place with working Back that restores scroll; `#anchors` smooth-scroll + highlight. [ ] Scroll is never lost across any of the above.
- Quick Look constraint: links render **styled but non-interactive** (no peek/sheet/fetch/nav).

---

### 8.3 Layer 3 — Identity & Reach (the differentiators; all stand on Layer 0)

**8.3.1 Theming.**
- Token-block swapping (the engine).
- **Built-in themes:** Claude (flagship, default) + curated cross-app palettes: **Catppuccin, Dracula, Nord, Tokyo Night, Rosé Pine, Gruvbox, Solarized** — light + dark where applicable.
- **Custom theme import:** user-supplied CSS/token file.
- **No-code tweak panel** (modeled on Obsidian's Style Settings): color pickers, font selector, reading width, spacing, font-size — adjusts tokens live without writing CSS.
- Acceptance: [ ] Switching a built-in theme retints the entire surface via tokens only. [ ] A custom token file loads and applies. [ ] The no-code panel changes the live document and persists. [ ] Theme applies identically in app + Quick Look.

**8.3.2 Accessibility / Focus pack** (all toggle-off; mostly token controls + small text transforms).
- Dyslexia fonts: **OpenDyslexic, Lexend** (bundled, OFL) selectable for `--font`.
- Reading ergonomics controls: width (`--measure`), line/letter/word spacing, `--fs-base` — exposed in UI.
- **Line-focus** (dim all but the current line/few lines).
- **Bionic mode** (bold word-beginnings).
- **Sepia / high-contrast** presets.
- **Dim-around-current-paragraph.**
- Acceptance: [ ] Each toggle works and is off by default. [ ] Font/width/spacing controls map to tokens. [ ] Line-focus and bionic mode render correctly and are reversible. [ ] Nothing here clutters the default reading surface.

**8.3.3 Beautiful sharing (growth loop).**
- Render a **selection or whole document** → **image in the current theme**, supporting **full GFM** (headings, tables, code, lists, callouts, Mermaid, math) — not just a single code block.
- No watermark.
- Optional: shareable rendered link.
- Acceptance: [ ] Exported image matches the on-screen theme exactly. [ ] Full-GFM content (incl. a table + Mermaid + math in one card) exports as one clean image. [ ] No watermark/branding burned in.

#### ▶ Release: **1.0 = Layers 0–3.**
Positioning at 1.0: *"A calm, private place to read what AI gives you — and it's yours."*

---

### 8.4 Layer 4 — Keep & Broaden (post-1.0)

- **8.4.1 AI conversation export reading** — ChatGPT/Claude/Gemini `.md` exports; conversation structure (turns, roles) rendered cleanly.
- **8.4.2 Highlights / annotations** — persisted locally; **exportable to Markdown/Obsidian**.
- **8.4.3 Listen / TTS** — with synchronized highlighting.
- Acceptance (per feature): [ ] AI exports render with clear turn structure. [ ] Highlights persist per document and export to Markdown. [ ] TTS reads the document with visible sync; pausable.

---

### 8.5 Layer 5 — Ecosystem & Longevity

- **8.5.1 Community theme gallery** — browse/preview/install community themes, with security discipline: **bundled assets, no remote network calls, vetting** before listing.
- **8.5.2 Cross-platform** (Tauri / web-frontend reuse) — **only if demand is demonstrated.**

---

## 9. Release plan & scope

| Release | Contents | Definition of done |
|---|---|---|
| **0.x (internal)** | Layers 0–2 | Backbone audit passes (8.0.2); core reading + links + outline solid. |
| **1.0** | Layers 0–3 | All Layer 0–3 acceptance criteria pass; positioning copy + repo README + screenshots ready. |
| **1.x** | Layer 4 | Per-feature acceptance; no regression to Invariants. |
| **2.x** | Layer 5 | Gated on community demand. |

**1.0 cut line is firm:** theming + accessibility/focus + sharing are *in*; editing, accounts, AI-in-app, and cross-platform are *out*.

---

## 10. Distribution & positioning (informative)

- Lead with **open source + free + local/private** — it is simultaneously a trust signal, an anti-subscription stance, and the exact reassurance readers want after cloud reading apps proved fragile.
- **Launch surfaces:** r/macapps and Show HN first (origin story + a GIF), then Product Hunt and lobste.rs; then audience rooms (r/ObsidianMD, r/ChatGPT, r/ClaudeAI; accessibility/ADHD communities when 8.3.2 ships).
- **Framing that wins** (matches what those communities upvote): *"I built this because I couldn't get Claude's reading experience anywhere else."* — the "I built X / fills a gap / honest comparison" archetype.
- **Sharing (8.3.3) is the passive loop:** every shared image is the product's aesthetic in the wild.
- **Stay small/focused and calm** — the texture that earns an unprompted "I use this, it's pretty good."

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Scope creep → bloat** (contradicts "small/focused") | Hard 1.0 cut line (Section 9); Non-Goals (4.2); every feature toggle-off (I4). |
| **Crowded viewer niche** (MDHero, MacMD, MarkView, OpenMark) | Differentiate on the *combination*: native + theme fidelity + accessibility + privacy + AI-output focus — not any single feature. |
| **Core not flawless** | Layer 0–2 fidelity + speed are the floor; nothing in Layer 3 ships until the core read is perfect. |
| **Theme/extension security** (shared themes) | Bundled assets, no remote calls, vetting (8.5.1); applies to any user/community CSS. |
| **Fonts/assets missing in Quick Look (no network)** | Everything a theme references is bundled; verified in the sandboxed extension. |

---

## 12. Open questions / decision log

**Decided**
- Reading face = **Source Serif 4** (OFL, bundled); mono = **JetBrains Mono**. Anthropic Serif/Tiempos/Copernicus/Styrene excluded (licensed).
- Colors = **exact extracted Claude Desktop tokens** (Section 7.1).
- Link default = **slide-over sheet**; live previews **app-only**, offline fallback in Quick Look.
- 1.0 = **Layers 0–3**.

**Open**
- [ ] Final product **name** (Reader vs **Margin** vs other).
- [ ] Link color default: **clay (`--accent`)** vs optional **blue** alternate.
- [ ] Shareable-link (8.3.3) — include in 1.0 or defer to 1.x?
- [ ] Sandboxed/notarized distribution timing (affects entitlements + previews network).

---

## 13. Sign-off

By signing, the parties commit to the **Invariants (§5)**, the **Token Contract (§7)**, the **Layer 0–3 = 1.0 scope (§9)**, and the **acceptance criteria (§8)**. Changes to any of these require a spec revision.

| Role | Name | Signature | Date |
|---|---|---|---|
| Product / Owner | Tirtha | _______________ | __________ |
| Design (Claude Design) | | _______________ | __________ |
| Engineering (Claude Code) | | _______________ | __________ |

---

*End of specification — Reader v1.0 (Draft for sign-off), 2026-06-28.*
