// Real-engine renderer checks in HEADLESS Chromium (no window, no focus theft).
// Covers what the jsdom suite deliberately skips because it has no layout/real JS
// engine: Mermaid diagrams, KaTeX math, and CSS custom-property (theme token)
// resolution. Run as part of `scripts/test.sh`.
//
// Requires the chromium browser binary once:  npx playwright install chromium
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { chromium } from "playwright";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const WR = join(dirname(fileURLToPath(import.meta.url)), "..", "WebResources");
const READER_URL = pathToFileURL(join(WR, "reader.html")).href;

const KITCHEN_SINK = [
  "# Title",
  "",
  "> [!NOTE]",
  "> A callout.",
  "",
  "Inline math $E = mc^2$ and display:",
  "",
  "$$\\int_0^1 x^2\\,dx = \\tfrac{1}{3}$$",
  "",
  "```mermaid",
  "graph TD; A-->B; B-->C;",
  "```",
  "",
  "```js",
  "const x = 1;",
  "```",
  "",
].join("\n");

let browser, page;

before(async () => {
  browser = await chromium.launch({ headless: true });
  page = await browser.newPage();
  await page.goto(READER_URL);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 10_000 });
  await page.evaluate((md) => window.__render(md, "kitchen.md", "/tmp", null, 0), KITCHEN_SINK);
});

after(async () => { await browser?.close(); });

test("markdown renders into the document article", async () => {
  const h1 = await page.textContent("#doc h1");
  assert.equal(h1?.trim(), "Title");
});

test("Mermaid renders a live SVG (real engine, not in jsdom)", async () => {
  await page.waitForSelector(".mermaid svg", { timeout: 15_000 });
  const svgCount = await page.locator(".mermaid svg").count();
  assert.ok(svgCount >= 1, "expected a rendered mermaid <svg>");
});

test("KaTeX renders math glyphs (real engine, not in jsdom)", async () => {
  await page.waitForSelector(".katex", { timeout: 15_000 });
  const katexCount = await page.locator("#doc .katex").count();
  assert.ok(katexCount >= 1, "expected KaTeX-rendered math");
});

test("theme tokens resolve via computed styles (needs a real CSS engine)", async () => {
  const bg = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()
  );
  assert.ok(bg.length > 0, "expected --bg design token to resolve to a value");
});

test("switching theme retints the resolved tokens", async () => {
  const before = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()
  );
  await page.evaluate(() => window.__applyTheme("claude-light"));
  const after = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()
  );
  assert.notEqual(before, after, "light/dark --bg should differ");
});
