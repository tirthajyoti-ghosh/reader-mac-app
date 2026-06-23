/* ============================================================================
   Reader renderer — shared by the app window AND the Quick Look extension.

   Swift injects content by calling:
     window.__render(markdownText)          parse + highlight + diagrams + math
     window.__setTheme('dark' | 'light')    flip data-theme (+ re-theme Mermaid)
     window.__matchCount(query)             occurrence count for the ⌘F bar
   Everything renders from locally bundled libs/fonts — no network.
   ============================================================================ */
(function () {
  "use strict";

  var doc = document.getElementById("doc");
  var scroller = document.getElementById("scroll");
  var progress = document.getElementById("progress");
  var root = document.documentElement;

  /* ---- markdown-it (GFM: tables + strikethrough on by default) ------------- */
  var md = window.markdownit({ html: true, linkify: true, typographer: false });

  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  /* fenced code: ```mermaid -> diagram container; else highlight.js -> palette */
  md.renderer.rules.fence = function (tokens, idx) {
    var t = tokens[idx];
    var info = (t.info || "").trim();
    var lang = info.split(/\s+/g)[0];
    if (lang === "mermaid") {
      return '<div class="mermaid">' + escapeHtml(t.content) + "</div>";
    }
    var body;
    try {
      if (lang && window.hljs.getLanguage(lang)) {
        body = window.hljs.highlight(t.content, { language: lang, ignoreIllegals: true }).value;
      } else {
        body = window.hljs.highlightAuto(t.content).value;
      }
    } catch (e) {
      body = escapeHtml(t.content);
    }
    return '<pre><code class="hljs language-' + escapeHtml(lang || "") + '">' + body + "</code></pre>";
  };

  /* ---- GitHub callouts: blockquote starting [!NOTE] -> tinted card ---------- */
  var CALLOUTS = { NOTE: "note", TIP: "tip", IMPORTANT: "important", WARNING: "warning", CAUTION: "caution" };
  function transformCallouts(container) {
    container.querySelectorAll("blockquote").forEach(function (bq) {
      var firstP = bq.querySelector("p");
      if (!firstP) return;
      var re = /^\s*\[!(\w+)\]\s*/i;
      var m = firstP.textContent.match(re);
      if (!m) return;
      var key = m[1].toUpperCase();
      var kind = CALLOUTS[key];
      if (!kind) return;

      firstP.innerHTML = firstP.innerHTML.replace(re, "");
      if (firstP.textContent.trim() === "" && !firstP.querySelector("img,code,a")) firstP.remove();

      var card = document.createElement("div");
      card.className = "callout " + kind;
      var title = document.createElement("div");
      title.className = "callout-title";
      title.textContent = key.charAt(0) + key.slice(1).toLowerCase(); // Note / Tip / ...
      var body = document.createElement("div");
      body.className = "callout-body";
      while (bq.firstChild) body.appendChild(bq.firstChild);
      card.appendChild(title);
      card.appendChild(body);
      bq.replaceWith(card);
    });
  }

  /* ---- GitHub task lists: - [ ] / - [x] -> styled .box control ------------- */
  function transformTaskLists(container) {
    container.querySelectorAll("li").forEach(function (li) {
      var re = /^(\s*<p>)?\s*\[([ xX])\]\s+/;
      var m = li.innerHTML.match(re);
      if (!m) return;
      var checked = m[2].toLowerCase() === "x";
      li.innerHTML = li.innerHTML.replace(re, m[1] || "");
      if (checked) li.classList.add("done");
      var box = document.createElement("span");
      box.className = "box";
      li.insertBefore(box, li.firstChild);
      if (li.parentElement) li.parentElement.classList.add("task-list");
    });
  }

  /* ---- Mermaid: theme variables pulled from the design tokens --------------- */
  function cssVar(name) { return getComputedStyle(root).getPropertyValue(name).trim(); }
  function mermaidThemeVars() {
    return {
      darkMode: root.getAttribute("data-theme") !== "light",
      background: cssVar("--bg"),
      primaryColor: cssVar("--surface"),
      primaryBorderColor: cssVar("--border"),
      primaryTextColor: cssVar("--text"),
      secondaryColor: cssVar("--code-bg"),
      tertiaryColor: cssVar("--code-bg"),
      secondaryBorderColor: cssVar("--border"),
      tertiaryBorderColor: cssVar("--border"),
      lineColor: cssVar("--muted"),
      textColor: cssVar("--text-2"),
      noteBkgColor: cssVar("--surface"),
      noteTextColor: cssVar("--text-2"),
      noteBorderColor: cssVar("--border"),
      fontFamily: cssVar("--mono") || "monospace",
    };
  }
  function initMermaid() {
    if (!window.mermaid) return;
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      themeVariables: mermaidThemeVars(),
      fontFamily: cssVar("--mono") || "monospace",
    });
  }
  function runMermaid(container) {
    if (!window.mermaid) return Promise.resolve();
    var nodes = Array.prototype.slice.call(container.querySelectorAll(".mermaid"));
    if (!nodes.length) return Promise.resolve();
    nodes.forEach(function (n) { if (n.dataset.src === undefined) n.dataset.src = n.textContent; });
    initMermaid();
    return window.mermaid.run({ nodes: nodes }).catch(function () {});
  }
  function reRenderMermaid() {
    if (!window.mermaid) return;
    var nodes = Array.prototype.slice.call(doc.querySelectorAll(".mermaid"));
    if (!nodes.length) return;
    nodes.forEach(function (n) {
      if (n.dataset.src !== undefined) {
        n.removeAttribute("data-processed");
        n.innerHTML = "";
        n.textContent = n.dataset.src;
      }
    });
    initMermaid();
    window.mermaid.run({ nodes: nodes }).catch(function () {});
  }

  /* ---- KaTeX: inline + display, all four delimiter styles ------------------ */
  function renderMath(container) {
    if (!window.renderMathInElement) return;
    try {
      window.renderMathInElement(container, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "$", right: "$", display: false },
          { left: "\\[", right: "\\]", display: true },
          { left: "\\(", right: "\\)", display: false },
        ],
        throwOnError: false,
        ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"],
      });
    } catch (e) {}
  }

  /* ---- signature: reading-progress hairline -------------------------------- */
  function updateProgress() {
    var m = scroller.scrollHeight - scroller.clientHeight;
    progress.style.setProperty("--progress", m > 0 ? (scroller.scrollTop / m).toFixed(3) : 0);
  }
  scroller.addEventListener("scroll", updateProgress, { passive: true });
  window.addEventListener("resize", updateProgress);

  /* ---- public API ---------------------------------------------------------- */
  var lastMarkdown = "";

  window.__render = function (text) {
    lastMarkdown = typeof text === "string" ? text : "";
    doc.innerHTML = md.render(lastMarkdown);
    transformCallouts(doc);
    transformTaskLists(doc);
    renderMath(doc);
    runMermaid(doc);
    scroller.scrollTop = 0;
    updateProgress();
  };

  window.__setTheme = function (t) {
    root.setAttribute("data-theme", t === "light" ? "light" : "dark");
    reRenderMermaid(); // Mermaid bakes colors into the SVG, so re-run on theme flip
  };

  window.__matchCount = function (q) {
    if (!q) return 0;
    var hay = (doc.textContent || "").toLowerCase();
    var needle = String(q).toLowerCase();
    if (!needle) return 0;
    var n = 0, i = 0;
    while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
    return n;
  };

  window.__ready = true;
})();
