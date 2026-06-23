# Reader — app icon assets

The mark is **"The Hairline"**: the app's signature clay reading-progress line
crowning a calm paragraph. It encodes the product in one glance — a document, rendered
beautifully — and owns the clay accent.

## Files

| File | Use |
|------|-----|
| `icon-dark.svg`   | **Primary app icon.** Warm near-black squircle, clay hairline. |
| `icon-light.svg`  | Light variant (cream squircle) if you ship a light-mode icon. |
| `icon-clay.svg`   | Bold all-clay alternate. |
| `icon-mono.svg`   | Monochrome (no accent) for contexts that forbid color. |
| `glyph-on-dark.svg` | Glyph only, no background — in-app lockup, About box, splash. Place on a dark surface. |
| `menubar-template.svg` | macOS menu-bar **template image** (solid black + alpha). |

All are pure vector (`viewBox 0 0 132 132`, corner radius 30 = 22.7%, matching the
macOS continuous-rounded-rect feel). They scale to any size with no quality loss.

## Color tokens (so the icon stays in sync with the app)

```
--bg      #1F1F1E   squircle (dark)        --accent  #D97757   clay hairline (dark)
--bg      #F8F8F6   squircle (light)       --accent  #C6613F   clay hairline (light)
text lines (dark):  #EDEBE4                text lines (light):  #26261F
```

## Setting the macOS app icon

1. **Rasterize** `icon-dark.svg` to PNGs at the standard sizes:
   `16, 32, 64, 128, 256, 512, 1024` px (plus @2x: `32, 64, 256, 512, 1024`).
   e.g. `rsvg-convert -w 1024 -h 1024 icon-dark.svg -o icon_512x512@2x.png`
   (or `sips` / `cairosvg` — any SVG rasterizer).
2. Drop them into `Assets.xcassets/AppIcon.appiconset` with the matching slots,
   **or** build an `.icns`:
   ```
   mkdir Reader.iconset
   # name each PNG icon_16x16.png, icon_16x16@2x.png … icon_512x512@2x.png
   iconutil -c icns Reader.iconset -o Reader.icns
   ```
3. **Full-bleed note:** these icons fill the whole canvas (the squircle *is* the art).
   That's intended for a self-contained look. If you'd rather follow Apple's exact
   icon grid (rounded-rect inset with transparent padding + system shadow), inset the
   artwork to ~80% and let the rounded rect sit centered — the vector makes this trivial.

## Menu-bar icon

Rasterize `menubar-template.svg` at `~18pt` (`18` and `36` px for @1x/@2x), add to the
asset catalog, and set **Render As → Template Image** (or suffix the name with
`Template`). macOS will tint it correctly for light and dark menu bars — do **not**
bake in color.

## Don'ts

- Don't add gradients, gloss, or drop shadows to the glyph — the restraint is the brand.
- Don't recolor the hairline to anything but the clay accent token.
- Keep the paragraph-line proportions; the clay line must stay the thinnest, topmost element.
