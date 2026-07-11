// Renderer regression suite — exercises the app.js render pipeline + the
// theming / accessibility / export APIs that Tracks T, A11y, and S added.
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeRenderer } from "./renderer-env.mjs";

test("L0–2: headings, links, callouts, task lists, outline", () => {
  const w = makeRenderer();
  w.__render(
    "# Title\n\n- [x] done\n- [ ] todo\n\n> [!NOTE]\n> a note\n\n" +
    "[ext](https://e.com) [int](./a.md) [anc](#title)\n\n## Second",
    "/x.md", "/", null, "0"
  );
  const doc = w.document.getElementById("doc");
  assert.equal(doc.querySelector("h1").textContent, "Title");
  assert.equal(doc.querySelector("h1").id, "title");                 // heading id (outline)
  assert.ok(doc.querySelector(".callout.note"), "callout");
  assert.equal(doc.querySelectorAll(".task-list .box").length, 2, "task boxes");
  assert.equal(doc.querySelector("li.done") ? 1 : 0, 1, "checked task");
  assert.ok(doc.querySelector("a.external"), "external link");
  assert.ok(doc.querySelector("a.internal"), "internal link");
  assert.ok(doc.querySelector("a.anchor"), "anchor link");
});

test("frontmatter renders as a metadata block, never a giant H1", () => {
  const w = makeRenderer();
  w.__render(
    "---\nname: proj\ndescription: \"a desc\"\nmetadata:\n  type: p\n  id: 42\n---\n\n## Body here",
    "/x.md", "/", null, "0"
  );
  const doc = w.document.getElementById("doc");
  assert.equal(doc.querySelectorAll("h1").length, 0, "no H1 from frontmatter");
  assert.ok(doc.querySelector(".frontmatter"), "frontmatter block");
  assert.equal(doc.querySelector(".fm-key").textContent, "name");
  assert.equal(doc.querySelectorAll(".fm-row").length, 5, "name/description/metadata/type/id rows");
  assert.equal(doc.querySelector("h2").textContent, "Body here", "body still renders");
});

test("a plain doc (no frontmatter) is untouched", () => {
  const w = makeRenderer();
  w.__render("# Real heading\n\ntext", "/y.md", "/", null, "0");
  const doc = w.document.getElementById("doc");
  assert.equal(doc.querySelector("h1").textContent, "Real heading");
  assert.equal(doc.querySelector(".frontmatter"), null);
});

test("find matches every occurrence, cross-node and with Bionic on", () => {
  const w = makeRenderer();
  w.__render("Retrieval and retrieval again in the text.", "/x.md", "/", null, "0");
  assert.equal(w.__find("retrieval").count, 2, "2 matches (case-insensitive)");
  assert.equal(w.document.querySelectorAll("mark.find-hit").length, 2);
  w.__clearFind();
  assert.equal(w.document.querySelectorAll("mark.find-hit").length, 0, "clear removes marks");

  w.__setBionic(true);
  assert.ok(w.document.querySelectorAll("b.bl").length > 0, "bionic wraps word-heads");
  assert.equal(w.__find("retrieval").count, 2, "find still works with bionic node-splits");
  w.__clearFind();
  w.__setBionic(false);
  assert.equal(w.document.querySelectorAll("b.bl").length, 0, "bionic fully reversed");
});

test("Bionic never alters textContent (outline/links/scroll stay valid)", () => {
  const w = makeRenderer();
  w.__render("# Retrieval findings\n\nsome words here", "/x.md", "/", null, "0");
  const before = w.document.querySelector("h1").textContent;
  const id = w.document.querySelector("h1").id;
  w.__setBionic(true);
  assert.equal(w.document.querySelector("h1").textContent, before, "textContent intact");
  assert.equal(w.document.querySelector("h1").id, id, "heading id intact");
  w.__setBionic(false);
});

test("theming: data-theme, data-reading preset, and token overrides", () => {
  const w = makeRenderer();
  const root = w.document.documentElement;
  w.__applyTheme("dracula");
  assert.equal(root.getAttribute("data-theme"), "dracula");
  w.__applyReadingPreset("sepia");
  assert.equal(root.getAttribute("data-reading"), "sepia");
  w.__clearReadingPreset();
  assert.equal(root.getAttribute("data-reading"), null);

  w.__setOverride("--accent", "#123456");
  assert.equal(root.style.getPropertyValue("--accent"), "#123456");
  w.__setOverride("--letter-spacing", "0.04em");
  assert.equal(root.style.getPropertyValue("--letter-spacing"), "0.04em");
  w.__clearOverride("--accent");
  assert.equal(root.style.getPropertyValue("--accent"), "");
  w.__clearOverrides();
  assert.equal(root.style.getPropertyValue("--letter-spacing"), "", "clearOverrides clears all");
});

test("A11y modes toggle classes on #doc and reverse cleanly", () => {
  const w = makeRenderer();
  w.__render("para one\n\npara two", "/x.md", "/", null, "0");
  const doc = w.document.getElementById("doc");
  w.__setDimParagraphs(true);
  assert.ok(doc.classList.contains("dim-para"));
  w.__setDimParagraphs(false);
  assert.ok(!doc.classList.contains("dim-para"));
  w.__setLineFocus(true);
  assert.ok(doc.classList.contains("focus-line"));
  assert.ok(doc.querySelectorAll("span.ln").length > 0, "lines wrapped");
  w.__setLineFocus(false);
  assert.ok(!doc.classList.contains("focus-line"));
  assert.equal(doc.querySelectorAll("span.ln").length, 0, "line wrap fully reversed");
});

test("export: whole-doc HTML strips chrome + reading artifacts", () => {
  const w = makeRenderer();
  w.__render("# Head\n\ntext with words", "/x/doc.md", "/x", null, "0");
  w.__setBionic(true);                       // add artifacts
  const html = w.__docHTML();
  assert.ok(html.includes("Head"), "content present");
  assert.ok(!/class="bl"/.test(html), "bionic <b class=bl> stripped");
  assert.ok(!/doc-path/.test(html), "doc-path chrome stripped");
  w.__setBionic(false);
});

test("export: buildExportCard frames the given HTML at a width preset", () => {
  const w = makeRenderer();
  w.__buildExportCard("<h2>Card</h2><p>body</p>", { snug: true, width: "docs", shadow: false });
  const card = w.document.querySelector("#__xhost .xcard");
  assert.ok(card, "card built");
  assert.ok(card.classList.contains("snug"), "snug padding");
  assert.ok(card.classList.contains("w-docs"), "docs width");
  assert.equal(card.querySelector("h2").textContent, "Card");
});
