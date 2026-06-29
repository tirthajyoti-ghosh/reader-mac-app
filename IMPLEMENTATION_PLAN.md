# Reader — Implementation Plan

> Companion to **PRODUCT_SPEC.md**. This document sequences the build across the two running sessions (**Claude Design**, **Claude Code**) and defines what is strictly ordered versus parallel-safe. It assumes the spec is signed off.

| Field | Value |
|---|---|
| Status | Active |
| Date | 2026-06-28 |
| Owner | Tirtha |
| Companion to | PRODUCT_SPEC.md (v1.0) |
| Scope | Path to 1.0 (spec Layers 0–3) |

---

## Context & governing rule

The running app predates the strict spec: it carries earlier eyeballed colors and almost certainly hardcoded visual values, and Layer 3 is greenfield. So the work is two movements: **(1) reconcile the backbone**, then **(2) build the three differentiators**.

**Governing rule (spec §6.3 / §8.0.2):** *Nothing in Layer 3 begins until the Token Contract audit passes — i.e. retheme is achievable by swapping the token block alone, with zero hardcoded visual values anywhere.* This is the one gate that the whole plan turns on.

---

## Phase 1 — Backbone reconciliation *(strictly sequential; gates everything)*

The only fully-blocking phase. Two ordered steps.

| Step | Session | Work | Depends on |
|---|---|---|---|
| **A1** | Claude **Design** | Emit the canonical `design-tokens.css` exactly per spec §7 — every token, both themes, the extracted Claude colors, Source Serif 4 / JetBrains Mono, and the reading-ergonomics tokens. Transcription, not exploration. Becomes the single source of truth. | Spec §7 |
| **A2** | Claude **Code** | Consume A1. **Strip every hardcoded visual value**, reconcile the running build's colors/fonts to §7, pass the §8.0.2 audit. Then **re-verify Layers 1–2** (reading surface, links, outline, live-reload) still pass after the refactor. | A1 |

- **A1 → A2 is sequential.** If the running build already matches §7, A2 collapses to a verification pass — but assume it doesn't.
- **Decision baked into A1:** link color = **clay (`--accent`)** per spec default, with a blue alternate kept as a flippable token. (Resolves the §12 link-color open item.)
- **Gate:** A2's §8.0.2 audit must pass before *any* Phase 2 work starts.

---

## Phase 2 — Layer 3 *(three parallel tracks)*

Once Phase 1 is green, the three differentiators are **mutually independent** (different surfaces, all depending only on the token contract), so the order *between* tracks does not matter. One shared dependency comes first.

### Pre-task P0 *(Design, small — do before T or A11y wire in)*
Design the **Reading Settings panel** container **once**. Both theming's no-code controls (§8.3.1) and the accessibility controls (§8.3.2) plug into it. If each track invents its own panel, you get two competing surfaces. This is the single coordination point across the tracks.

### The tracks

Within each track, the **Code plumbing depends only on Phase 1, not on the Design comps** — so Design and Code can run *simultaneously* inside a track, merging when the comps land.

| Track | Spec | Code (needs Phase 1[+P0]) | Design (parallel) | Scope gate |
|---|---|---|---|---|
| **T — Theming** | §8.3.1 | Token-swap engine + custom-CSS import | Picker + no-code panel comps; curated palette token sets (Catppuccin/Dracula/Nord/Tokyo Night/Rosé Pine/Gruvbox/Solarized) | Palettes drop in any time after the engine exists |
| **A11y — Accessibility/Focus** | §8.3.2 | Bundle OpenDyslexic/Lexend; spacing/width/size token controls; bionic + line-focus transforms; sepia/contrast/dim toggles | Control presentation + focus/bionic/dim visual states | Needs P0 |
| **S — Sharing** | §8.3.3 | DOM→image capture in current theme, full GFM | Export presets / framing | Resolve §12: shareable **link** in 1.0 or defer to 1.x — before finalizing |

---

## Ordering decision: strict vs free

**Order MATTERS (sequential):**
- A1 before A2.
- All of Phase 1 before any of Phase 2.
- Pre-task **P0** (settings container) before Track **T**'s panel and Track **A11y**'s controls wire in.
- Design comps before Code implementation *within a single feature*.

**Order does NOT matter (parallel-safe):**
- The three Layer-3 tracks relative to each other.
- The built-in palette token sets (any order, anytime after the swap engine).
- Each track's Code plumbing built alongside its own Design exploration.
- **Design running a feature ahead of Code across the whole plan** (see cadence).

---

## Cadence for a solo orchestrator

One person driving two sessions means true 3-way parallelism isn't real — but a **pipeline** is. Keep **Claude Design one feature ahead of Claude Code**:

```
Design:  A1 ─▶ P0 ─▶ T comps ─▶ A11y spec ─▶ S presets
Code:         A2 ──────────▶ T build ─▶ A11y build ─▶ S build
                              (each Code task starts when its Design output is ready)
```

Neither session sits blocked, and you're never the bottleneck.

### Recommended track priority (executed roughly serially)
**Theming → Accessibility → Sharing.**
- **Theming first:** the flagship; establishes the shared settings panel A11y reuses; the hardest proof the token contract holds.
- **Accessibility second:** cheap once tokens + panel exist.
- **Sharing last:** most independent and launch-timed — can run parallel to either, but finalize last so shared cards showcase a real theme.

---

## 1.0 gate

- [ ] All spec §8 Layer 0–3 acceptance boxes green.
- [ ] §8.0.2 token audit passed (backbone clean).
- [ ] §12 opens resolved (name + sandbox-timing don't block the build; settle by launch).
- [ ] README + screenshots ready.

---

## Session map (quick reference)

| Order | Task | Session | Parallel with |
|---|---|---|---|
| 1 | A1 — canonical tokens | Design | — |
| 2 | A2 — de-hardcode + reconcile + audit + re-verify L1–2 | Code | — |
| 3 | P0 — Reading Settings container | Design | — |
| 4 | T — theming | Code + Design | (Design can start A11y spec) |
| 5 | A11y — accessibility/focus | Code + Design | (Design can start S presets) |
| 6 | S — sharing | Code + Design | — |
| 7 | 1.0 gate | Owner | — |

---

*End of implementation plan — companion to PRODUCT_SPEC.md, 2026-06-28.*
