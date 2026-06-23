#!/usr/bin/env bash
# Vendor all JS libs + woff2 fonts locally so the renderer works fully OFFLINE
# (the Quick Look extension is sandboxed with no network). Re-run to refresh.
#
# Resolved into WebResources/vendor + WebResources/fonts. Those ARE committed;
# this script only needs running to (re)generate them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/WebResources/vendor"
FONTS="$ROOT/WebResources/fonts"
TMP="$ROOT/scripts/.vendor-tmp"

# Pinned versions
MDIT="markdown-it@14.1.0"
HLJS="@highlightjs/cdn-assets@11.10.0"
MERMAID="mermaid@11.4.1"
KATEX="katex@0.16.11"
SANS="@fontsource/source-sans-3@5.2.5"
MONO="@fontsource/jetbrains-mono@5.1.0"

rm -rf "$TMP"; mkdir -p "$TMP" "$VENDOR" "$FONTS" "$VENDOR/katex/fonts"

echo "==> downloading packages with npm pack into $TMP"
( cd "$TMP" && npm pack "$MDIT" "$HLJS" "$MERMAID" "$KATEX" "$SANS" "$MONO" >/dev/null )
for tgz in "$TMP"/*.tgz; do tar -xzf "$tgz" -C "$TMP"; done
# npm pack extracts every package into ./package — extract each separately
rm -rf "$TMP/pkgs"; mkdir -p "$TMP/pkgs"
i=0
for tgz in "$TMP"/*.tgz; do
  d="$TMP/pkgs/$i"; mkdir -p "$d"; tar -xzf "$tgz" -C "$d"; i=$((i+1))
done

# helper: find first matching file under the extracted packages
find1() { find "$TMP/pkgs" -type f -path "$1" 2>/dev/null | head -1; }

echo "==> markdown-it"
cp "$(find1 '*/package/dist/markdown-it.min.js')" "$VENDOR/markdown-it.min.js"

echo "==> highlight.js (browser bundle, common languages)"
cp "$(find1 '*/package/highlight.min.js')" "$VENDOR/highlight.min.js"

echo "==> mermaid"
MERMAID_UMD="$(find1 '*/package/dist/mermaid.min.js' || true)"
if [ -n "${MERMAID_UMD:-}" ]; then
  cp "$MERMAID_UMD" "$VENDOR/mermaid.min.js"; echo "    using UMD dist/mermaid.min.js"
else
  cp "$(find1 '*/package/dist/mermaid.esm.min.mjs')" "$VENDOR/mermaid.esm.min.mjs"
  # bundled chunks needed by the ESM build
  find "$TMP/pkgs" -type f -path '*/package/dist/chunks/*' -exec sh -c '
    rel="${1#*/package/dist/}"; mkdir -p "'"$VENDOR"'/$(dirname "$rel")"; cp "$1" "'"$VENDOR"'/$rel"' _ {} \;
  echo "    using ESM mermaid.esm.min.mjs (+ chunks)"
fi

echo "==> katex (js + css + contrib + fonts)"
cp "$(find1 '*/package/dist/katex.min.js')"  "$VENDOR/katex/katex.min.js"
cp "$(find1 '*/package/dist/katex.min.css')" "$VENDOR/katex/katex.min.css"
cp "$(find1 '*/package/dist/contrib/auto-render.min.js')" "$VENDOR/katex/auto-render.min.js"
find "$TMP/pkgs" -type f -path '*/package/dist/fonts/*.woff2' -exec cp {} "$VENDOR/katex/fonts/" \;

echo "==> fonts: Source Sans 3 (latin) 400 / 600 / 700 + 400 italic"
cp "$(find1 '*/source-sans-3-latin-400-normal.woff2')" "$FONTS/SourceSans3-Regular.woff2"
cp "$(find1 '*/source-sans-3-latin-600-normal.woff2')" "$FONTS/SourceSans3-SemiBold.woff2"
cp "$(find1 '*/source-sans-3-latin-700-normal.woff2')" "$FONTS/SourceSans3-Bold.woff2"
cp "$(find1 '*/source-sans-3-latin-400-italic.woff2')" "$FONTS/SourceSans3-Italic.woff2"

echo "==> fonts: JetBrains Mono (latin) Regular + Bold"
cp "$(find1 '*/jetbrains-mono-latin-400-normal.woff2')" "$FONTS/JetBrainsMono-Regular.woff2"
cp "$(find1 '*/jetbrains-mono-latin-700-normal.woff2')" "$FONTS/JetBrainsMono-Bold.woff2"

rm -rf "$TMP"

echo ""
echo "==> vendored manifest"
( cd "$ROOT" && find WebResources/vendor WebResources/fonts -type f | sort | while read -r f; do
    printf '   %8s  %s\n' "$(wc -c < "$f")" "$f"; done )
echo "==> done."
