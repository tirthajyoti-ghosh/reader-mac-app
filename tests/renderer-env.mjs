// Loads the REAL renderer (reader.html DOM + vendored markdown-it/highlight + app.js)
// into a jsdom window so the renderer's DOM logic can be unit-tested in Node.
// Browser-integration paths (window.webkit, IntersectionObserver, mermaid/katex,
// selectionchange) are feature-detected in app.js and simply skipped here.
// Layout-dependent behaviour (line-focus visual wrapping, theme token resolution)
// needs a real engine and is covered by the browser checks, not jsdom.
import { JSDOM } from "jsdom";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const WR = join(dirname(fileURLToPath(import.meta.url)), "..", "WebResources");

export function makeRenderer() {
  const dom = new JSDOM(
    `<!DOCTYPE html><html lang="en" data-theme="claude-dark"><head></head><body>
       <div class="rdr">
         <div class="reading-progress" id="progress"><i></i></div>
         <div class="scroll" id="scroll"><article class="md" id="doc"></article></div>
       </div>
     </body></html>`,
    { runScripts: "dangerously", pretendToBeVisual: true }
  );
  const { window } = dom;
  // jsdom has no layout engine; stub the rect APIs the line-focus wrapper calls so
  // it runs (each block collapses to one .ln — enough to test toggle/reverse; the
  // real per-visual-line splitting is verified in a browser).
  const rect = { top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0 };
  if (!window.Range.prototype.getClientRects)
    window.Range.prototype.getClientRects = () => [rect];
  window.Element.prototype.getBoundingClientRect = () => ({ ...rect });
  for (const f of ["vendor/markdown-it.min.js", "vendor/highlight.min.js", "app.js"]) {
    const s = window.document.createElement("script");
    s.textContent = readFileSync(join(WR, f), "utf8");
    window.document.body.appendChild(s);
  }
  if (!window.__ready) throw new Error("app.js failed to initialise in jsdom");
  return window;
}
