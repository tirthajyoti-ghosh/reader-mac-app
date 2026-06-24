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

  /* ---- lazy-load heavy libs (Mermaid / KaTeX) only when a doc needs them ---- */
  function loadScript(src, done) {
    var s = document.createElement("script");
    s.src = src; s.async = false;
    s.onload = function () { done(); };
    s.onerror = function () { done(); };   // fail-safe: don't block render
    document.head.appendChild(s);
  }
  var katexState = 0, katexQueue = [];     // 0 = not loaded, 1 = loading, 2 = ready
  function ensureKatex(cb) {
    if (window.renderMathInElement) { cb(); return; }
    katexQueue.push(cb);
    if (katexState === 1) return;
    katexState = 1;
    loadScript("./vendor/katex/katex.min.js", function () {
      loadScript("./vendor/katex/auto-render.min.js", function () {
        katexState = 2;
        var q = katexQueue; katexQueue = [];
        q.forEach(function (f) { f(); });
      });
    });
  }
  var mermaidState = 0, mermaidQueue = [];
  function ensureMermaid(cb) {
    if (window.mermaid) { cb(); return; }
    mermaidQueue.push(cb);
    if (mermaidState === 1) return;
    mermaidState = 1;
    loadScript("./vendor/mermaid.min.js", function () {
      mermaidState = 2;
      var q = mermaidQueue; mermaidQueue = [];
      q.forEach(function (f) { f(); });
    });
  }

  /* ---- signature: reading-progress hairline -------------------------------- */
  function updateProgress() {
    var m = scroller.scrollHeight - scroller.clientHeight;
    progress.style.setProperty("--progress", m > 0 ? (scroller.scrollTop / m).toFixed(3) : 0);
  }
  scroller.addEventListener("scroll", updateProgress, { passive: true });
  window.addEventListener("resize", updateProgress);

  /* ============================================================================
     LINK SURFACE — a link is a DETOUR, not a destination. Classify links so they
     telegraph their target, intercept activation, peek on hover. Routing happens
     Swift-side (the doc webview stays mounted, so scroll is preserved for free).
     In Quick Look (no bridge) links are styled but non-interactive.
     ============================================================================ */
  var INTERACTIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.link);
  function postLink(p) { if (INTERACTIVE) window.webkit.messageHandlers.link.postMessage(p); }
  function postPeek(p) { if (INTERACTIVE && window.webkit.messageHandlers.peek) window.webkit.messageHandlers.peek.postMessage(p); }

  var MD_EXT = /\.(md|markdown|mdown|mkd|mdwn|mdtext)(?:[#?].*)?$/i;
  var WIFI_OFF_SVG = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 8.5a16 16 0 0 1 20 0"/><path d="M5 12.5a11 11 0 0 1 14 0"/><path d="M8.5 16a6 6 0 0 1 7 0"/><path d="M12 20h.01"/><path d="m2 2 20 20"/></svg>';
  var DOC_SVG = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--muted)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4"/><path d="M17 21H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7l5 5v11a2 2 0 0 1-2 2Z"/></svg>';

  function slugify(s) {
    return (s || "").toLowerCase().trim().replace(/[^\w\s-]/g, "").replace(/\s+/g, "-").replace(/-+/g, "-");
  }
  function addHeadingIds(container) {
    var used = {};
    container.querySelectorAll("h1,h2,h3,h4,h5,h6").forEach(function (h) {
      if (h.id) { used[h.id] = 1; return; }
      var base = slugify(h.textContent) || "section", id = base, n = 2;
      while (used[id]) { id = base + "-" + n; n++; }
      used[id] = 1; h.id = id;
    });
  }
  function domainOf(href) {
    try { return new URL(href).hostname.replace(/^www\./, ""); }
    catch (e) { return (href || "").split("/")[2] || href; }
  }
  function resolveInternal(href, docDir) {
    var hash = "", q = href.indexOf("#");
    if (q >= 0) { hash = href.slice(q); href = href.slice(0, q); }
    if (/^([a-z]+:)?\/\//i.test(href) || href.charAt(0) === "/") return href + hash;
    if (!docDir) return href + hash;
    var parts = (docDir + "/" + href).split("/"), out = [];
    parts.forEach(function (seg) {
      if (seg === "" || seg === ".") return;
      if (seg === "..") { out.pop(); return; }
      out.push(seg);
    });
    return "/" + out.join("/") + hash;
  }
  var visitedSet = {};
  function classifyLinks(container, docDir) {
    container.querySelectorAll("a[href]").forEach(function (a) {
      var href = a.getAttribute("href") || "";
      if (href.charAt(0) === "#") { a.classList.add("anchor"); return; }
      if (MD_EXT.test(href)) {
        a.classList.add("internal");
        a.dataset.target = resolveInternal(href, docDir);
        return;
      }
      a.classList.add("external");
      a.dataset.target = href;
      if (visitedSet[href]) a.classList.add("visited");
    });
  }
  function linkKind(a) {
    return a.classList.contains("internal") ? "internal"
         : a.classList.contains("anchor") ? "anchor" : "external";
  }
  function scrollToAnchor(frag) {
    var id = (frag || "").replace(/^#/, "");
    var el = document.getElementById(id) || document.getElementById(slugify(decodeURIComponent(id)));
    if (!el) return;
    el.scrollIntoView({ behavior: "smooth", block: "start" });
    el.classList.remove("flash"); void el.offsetWidth; el.classList.add("flash");
    setTimeout(function () { el.classList.remove("flash"); }, 1300);
  }
  window.__scrollToAnchor = scrollToAnchor;
  window.__markVisited = function (href) {
    visitedSet[href] = 1;
    doc.querySelectorAll("a.external").forEach(function (a) {
      if ((a.dataset.target || a.getAttribute("href")) === href) a.classList.add("visited");
    });
  };
  window.__getScroll = function () { return scroller.scrollTop; };
  window.__setScroll = function (t) { scroller.scrollTop = t || 0; updateProgress(); };

  function prependBreadcrumb(name) {
    if (!name) return;
    var b = document.createElement("div");
    b.className = "breadcrumb";
    b.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 19-7-7 7-7"/><path d="M19 12H5"/></svg><span>Back to <span class="src"></span></span>';
    b.querySelector(".src").textContent = name;
    b.addEventListener("click", function () { postLink({ event: "back" }); });
    doc.insertBefore(b, doc.firstChild);
  }

  /* clicks / right-clicks (anchors handled locally; rest routed to Swift) */
  doc.addEventListener("click", function (e) {
    var a = e.target.closest ? e.target.closest("a[href]") : null;
    if (!a) return;
    e.preventDefault();
    hidePeek();
    if (linkKind(a) === "anchor") { scrollToAnchor(a.getAttribute("href")); return; }
    postLink({ event: "click", href: a.dataset.target || a.getAttribute("href"),
               kind: linkKind(a), text: (a.textContent || "").trim(),
               cmd: !!e.metaKey, alt: !!e.altKey, shift: !!e.shiftKey, ctrl: !!e.ctrlKey });
  }, true);
  doc.addEventListener("contextmenu", function (e) {
    var a = e.target.closest ? e.target.closest("a[href]") : null;
    if (!a || linkKind(a) === "anchor") return;
    e.preventDefault();
    postLink({ event: "contextmenu", href: a.dataset.target || a.getAttribute("href"),
               kind: linkKind(a), text: (a.textContent || "").trim() });
  }, true);

  /* hover peek */
  var peekTimer = null, peekCard = null, peekAnchor = null, peekSeq = 0, peekCache = {}, peekX = 0, peekY = 0;
  function hidePeek() { clearTimeout(peekTimer); if (peekCard) { peekCard.remove(); peekCard = null; } peekAnchor = null; }
  window.__hidePeek = hidePeek;
  doc.addEventListener("mouseover", function (e) {
    var a = e.target.closest ? e.target.closest("a[href]") : null;
    if (!a || linkKind(a) === "anchor") return;
    if (a === peekAnchor) return;
    clearTimeout(peekTimer);
    peekX = e.clientX; peekY = e.clientY;
    peekTimer = setTimeout(function () { requestPeek(a); }, 250);
  });
  doc.addEventListener("mouseout", function (e) {
    var a = e.target.closest ? e.target.closest("a[href]") : null;
    if (a) clearTimeout(peekTimer);
  });
  function requestPeek(a) {
    var href = a.dataset.target || a.getAttribute("href"), kind = linkKind(a);
    peekAnchor = a;
    var seq = ++peekSeq;
    if (peekCache[href]) { showPeek(peekCache[href], seq); return; }
    if (!INTERACTIVE) { showPeek({ offline: true, kind: kind, href: href, domain: domainOf(href) }, seq); return; }
    postPeek({ id: seq, href: href, kind: kind });
  }
  window.__peekResult = function (id, data) {
    if (id !== peekSeq) return;
    if (data && data.href) peekCache[data.href] = data;
    showPeek(data, id);
  };
  function showPeek(data, seq) {
    if (seq !== peekSeq) return;
    if (peekCard) peekCard.remove();
    var d = data || {}, card = document.createElement("div");
    card.className = "peek" + (d.offline ? " offline" : "");
    var html;
    if (d.offline) {
      html = '<div class="peek-body"><div class="peek-head"><span class="peek-favicon" style="background:var(--border);color:var(--muted);">↗</span><span class="peek-domain"></span></div><div class="peek-title"></div><div class="peek-offline-note">' + WIFI_OFF_SVG + 'Preview unavailable offline</div></div><div class="peek-actions"><button class="peek-btn primary" data-act="open">Open</button><span class="sep">·</span><button class="peek-btn" data-act="browser">Browser ↗</button></div>';
    } else if (d.kind === "internal") {
      html = '<div class="peek-body"><div class="peek-head">' + DOC_SVG + '<span class="peek-domain"></span></div></div><div class="peek-snippet"><article class="md" style="padding:0;max-width:none;font-size:14px;line-height:1.55;"></article></div><div class="peek-actions"><button class="peek-btn primary" data-act="open">Open</button><span class="sep">·</span><button class="peek-btn" data-act="split">Open in split</button></div>';
    } else {
      html = (d.image ? '<div class="peek-thumb" data-img></div>' : "") + '<div class="peek-body"><div class="peek-head"><span class="peek-favicon" data-fav></span><span class="peek-domain"></span></div><div class="peek-title"></div><div class="peek-desc"></div></div><div class="peek-actions"><button class="peek-btn primary" data-act="open">Open</button><span class="sep">·</span><button class="peek-btn" data-act="split">Open in split</button><span class="sep">·</span><button class="peek-btn" data-act="browser">Browser ↗</button></div>';
    }
    card.innerHTML = html;
    var set = function (sel, val) { var el = card.querySelector(sel); if (el && val != null) el.textContent = val; };
    set(".peek-domain", d.domain || domainOf(d.href || ""));
    set(".peek-title", d.title || d.href || "");
    set(".peek-desc", d.description || "");
    var fav = card.querySelector("[data-fav]"); if (fav) fav.textContent = ((d.site || d.domain || "•") + "").charAt(0).toUpperCase();
    var thumb = card.querySelector("[data-img]"); if (thumb && d.image) thumb.style.backgroundImage = "url('" + ("" + d.image).replace(/'/g, "%27") + "')";
    var snip = card.querySelector(".peek-snippet .md"); if (snip && d.snippet) snip.innerHTML = md.render(d.snippet);
    card.querySelectorAll(".peek-btn").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        postLink({ event: "peekAction", action: btn.getAttribute("data-act"), href: d.href, kind: d.kind || "external" });
        hidePeek();
      });
    });
    card.style.position = "fixed"; card.style.zIndex = "60";
    card.style.left = Math.max(8, Math.min(peekX, window.innerWidth - (d.offline ? 296 : 356))) + "px";
    card.style.top = Math.min(peekY + 12, window.innerHeight - 250) + "px";
    card.addEventListener("mouseleave", hidePeek);
    document.body.appendChild(card);
    peekCard = card;
  }

  /* ---- public API ---------------------------------------------------------- */
  var lastMarkdown = "";
  var findHits = [];
  var findPos = -1;

  // Document path caption — prepended above the first heading, inside .md.
  function prependDocPath(path) {
    if (!path) return;
    var slash = path.lastIndexOf("/");
    var dir = slash >= 0 ? path.slice(0, slash + 1) : "";
    var name = slash >= 0 ? path.slice(slash + 1) : path;
    var wrap = document.createElement("div");
    wrap.className = "doc-path";
    wrap.title = path;
    wrap.innerHTML =
      '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/></svg>' +
      '<span class="p-dir"></span><span class="p-name"></span>';
    wrap.querySelector(".p-dir").textContent = dir;   // textContent → no HTML injection from paths
    wrap.querySelector(".p-name").textContent = name;
    // optional: click to reveal in Finder (app only; the handler is absent in Quick Look)
    var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.revealFile;
    if (mh) {
      wrap.classList.add("revealable");
      wrap.addEventListener("click", function () { mh.postMessage(""); });
    }
    doc.insertBefore(wrap, doc.firstChild);
  }

  window.__render = function (text, path, docDir, breadcrumb, restoreScroll) {
    findHits = [];           // doc is replaced below; any old marks go with it
    findPos = -1;
    hidePeek();
    lastMarkdown = typeof text === "string" ? text : "";
    doc.innerHTML = md.render(lastMarkdown);
    addHeadingIds(doc);
    classifyLinks(doc, docDir);
    transformCallouts(doc);
    transformTaskLists(doc);
    prependDocPath(path);
    prependBreadcrumb(breadcrumb && breadcrumb.name);   // above the doc-path, if navigated in
    // Only pull in KaTeX / Mermaid for docs that actually use them.
    if (/\$|\\\(|\\\[/.test(lastMarkdown)) ensureKatex(function () { renderMath(doc); });
    if (doc.querySelector(".mermaid")) ensureMermaid(function () { runMermaid(doc); });
    scroller.scrollTop = restoreScroll || 0;
    updateProgress();
  };

  window.__setTheme = function (t) {
    root.setAttribute("data-theme", t === "light" ? "light" : "dark");
    reRenderMermaid(); // Mermaid bakes colors into the SVG, so re-run on theme flip
  };

  /* ---- find: highlight every match, cycle the current one ------------------ */
  function clearFind() {
    if (findHits.length) {
      var parents = [];
      findHits.forEach(function (m) {
        var p = m.parentNode;
        if (!p) return;
        p.replaceChild(document.createTextNode(m.textContent), m);
        if (parents.indexOf(p) === -1) parents.push(p);
      });
      parents.forEach(function (p) { p.normalize(); });
    }
    findHits = [];
    findPos = -1;
  }

  function highlightAll(query) {
    clearFind();
    var needle = (query || "").toLowerCase();
    if (!needle) return 0;
    var walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !/\S/.test(node.nodeValue)) return NodeFilter.FILTER_REJECT;
        var p = node.parentNode;
        while (p && p !== doc) {
          var tag = p.nodeName;
          if (tag === "SCRIPT" || tag === "STYLE" || tag === "MARK") return NodeFilter.FILTER_REJECT;
          if (p.classList && p.classList.contains("doc-path")) return NodeFilter.FILTER_REJECT;
          p = p.parentNode;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [], n;
    while ((n = walker.nextNode())) nodes.push(n);

    nodes.forEach(function (node) {
      var text = node.nodeValue, lower = text.toLowerCase();
      var idx = lower.indexOf(needle);
      if (idx === -1) return;
      var frag = document.createDocumentFragment(), last = 0;
      while (idx !== -1) {
        if (idx > last) frag.appendChild(document.createTextNode(text.slice(last, idx)));
        var mark = document.createElement("mark");
        mark.className = "find-hit";
        mark.textContent = text.slice(idx, idx + needle.length);
        frag.appendChild(mark);
        findHits.push(mark);
        last = idx + needle.length;
        idx = lower.indexOf(needle, last);
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(frag, node);
    });
    return findHits.length;
  }

  function setCurrent(i) {
    if (!findHits.length) return;
    if (findPos >= 0 && findHits[findPos]) findHits[findPos].classList.remove("current");
    findPos = ((i % findHits.length) + findHits.length) % findHits.length;
    var cur = findHits[findPos];
    cur.classList.add("current");
    cur.scrollIntoView({ block: "center", inline: "nearest" });
  }

  window.__find = function (query) {
    // Highlight every match but don't select one yet — Enter / ⌘F navigates,
    // first to the opening match, then cycling through the rest.
    var count = highlightAll(query);
    return { count: count, index: 0 };
  };
  window.__findNext = function () {
    if (!findHits.length) return { count: 0, index: 0 };
    setCurrent(findPos + 1);
    return { count: findHits.length, index: findPos + 1 };
  };
  window.__findPrev = function () {
    if (!findHits.length) return { count: 0, index: 0 };
    setCurrent(findPos - 1);
    return { count: findHits.length, index: findPos + 1 };
  };
  window.__clearFind = function () { clearFind(); };

  window.__ready = true;
})();
