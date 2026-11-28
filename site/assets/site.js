// The documentation site's page: the current page in the tree and the
// groups around it opened, breadcrumbs, the page's contents, search, the
// light and dark toggle (with the screenshots of the theme shown), the menu
// on narrow screens, Mermaid diagrams and wide tables.
(function () {
  "use strict";
  var root = document.documentElement;
  var script = document.currentScript;

  function store(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }
  function stored(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
  function el(tag, attrs, text) {
    var node = document.createElement(tag);
    for (var name in attrs || {}) node.setAttribute(name, attrs[name]);
    if (text) node.textContent = text;
    return node;
  }
  function path(href) {
    return new URL(href, location.href).pathname.replace(/index\.html$/, "").replace(/\.html$/, "");
  }

  // ---- the tree: the current page, the groups around it open ----------
  var here = path(location.href);
  var current = null;
  document.querySelectorAll("#explorer a").forEach(function (a) {
    if (!current && path(a.href) === here) current = a;
  });
  document.querySelectorAll("#explorer details").forEach(function (d) {
    var key = "nav:" + d.querySelector("summary").textContent.trim();
    var s = stored(key);
    if (s === "open") d.open = true;
    if (s === "closed") d.open = false;
    d.addEventListener("toggle", function () { store(key, d.open ? "open" : "closed"); });
  });
  var crumbs = [];
  if (current) {
    current.setAttribute("aria-current", "page");
    for (var n = current.parentElement; n && n.id !== "explorer"; n = n.parentElement) {
      if (n.tagName === "DETAILS") {
        n.open = true;
        var title = n.querySelector("summary");
        if (!title.contains(current)) crumbs.unshift(title.querySelector("a, span"));
      }
    }
    current.scrollIntoView({ block: "nearest" });
  }
  var bar = document.getElementById("breadcrumbs");
  crumbs.forEach(function (c) {
    var span = el("span");
    span.appendChild(c.tagName === "A" ? el("a", { href: c.href }, c.textContent) : document.createTextNode(c.textContent));
    bar.appendChild(span);
  });
  if (current && crumbs.length) bar.appendChild(el("span", {}, current.textContent));

  // ---- the page's contents ------------------------------------------
  var heads = document.querySelectorAll("article h2[id], article h3[id]");
  var toc = document.getElementById("toc");
  if (heads.length > 1) {
    toc.appendChild(el("h2", {}, "On this page"));
    var list = el("ul");
    var sub = null;
    heads.forEach(function (h) {
      var li = el("li");
      li.appendChild(el("a", { href: "#" + h.id }, h.textContent));
      if (h.tagName === "H3" && list.lastChild) {
        if (!sub) { sub = el("ul"); list.lastChild.appendChild(sub); }
        sub.appendChild(li);
      } else {
        sub = null;
        list.appendChild(li);
      }
    });
    toc.appendChild(list);
    // the section being read
    var links = toc.querySelectorAll("a");
    var mark = function () {
      var at = null;
      heads.forEach(function (h, i) { if (h.getBoundingClientRect().top < 120) at = i; });
      links.forEach(function (a, i) { a.classList.toggle("here", i === at); });
    };
    addEventListener("scroll", mark, { passive: true });
    mark();
  }

  // ---- light and dark, and the screenshots of each ---------------------
  // A screenshot is a <picture> with a dark source for
  // (prefers-color-scheme: dark), which GitHub shows by the reader's system;
  // here it follows the toggle.
  var pictures = [];
  document.querySelectorAll("article picture source[media*='prefers-color-scheme']").forEach(function (s) {
    pictures.push({ source: s, dark: /dark/.test(s.getAttribute("media")) });
  });
  function theme(t) {
    root.dataset.theme = t;
    pictures.forEach(function (p) { p.source.media = p.dark === (t === "dark") ? "all" : "not all"; });
  }
  theme(root.dataset.theme);
  document.getElementById("theme-toggle").addEventListener("click", function () {
    var t = root.dataset.theme === "dark" ? "light" : "dark";
    theme(t);
    store("theme", t);
  });

  // ---- the menu, on narrow screens -----------------------------------
  var menu = document.getElementById("menu-toggle");
  function setMenu(open) {
    if (open) root.dataset.menu = "open"; else delete root.dataset.menu;
    menu.setAttribute("aria-expanded", open ? "true" : "false");
  }
  menu.addEventListener("click", function () { setMenu(root.dataset.menu !== "open"); });
  document.getElementById("menu-backdrop").addEventListener("click", function () { setMenu(false); });

  // ---- search: the pages' titles, headings and text (search.json) --------
  var input = document.getElementById("search-input");
  var results = document.getElementById("search-results");
  var pages = null;
  function load() {
    if (!pages) {
      // the index's text keeps HTML's entities (&lt;): read as the page shows them
      var decode = function (t) { return new DOMParser().parseFromString(t, "text/html").documentElement.textContent; };
      pages = fetch(input.dataset.index).then(function (r) { return r.json(); }).then(function (all) {
        all.forEach(function (p) { p.title = decode(p.title); p.headings = decode(p.headings); p.text = decode(p.text); });
        return all;
      }).catch(function () { return []; });
    }
    return pages;
  }
  function show() {
    var terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) { results.hidden = true; return; }
    load().then(function (all) {
      var hits = [];
      all.forEach(function (p) {
        var title = p.title.toLowerCase(), heads = p.headings.toLowerCase(), text = p.text.toLowerCase(), score = 0;
        for (var i = 0; i < terms.length; i++) {
          var t = terms[i];
          var s = (title.indexOf(t) >= 0 ? 10 : 0) + (heads.indexOf(t) >= 0 ? 3 : 0) + (text.indexOf(t) >= 0 ? 1 : 0);
          if (!s) return;
          score += s;
        }
        hits.push({ page: p, score: score, at: text.indexOf(terms[0]) });
      });
      hits.sort(function (a, b) { return b.score - a.score; });
      results.textContent = "";
      if (!hits.length) results.appendChild(el("p", {}, "Nothing found"));
      hits.slice(0, 20).forEach(function (h) {
        var a = el("a", { href: h.page.url });
        a.appendChild(el("strong", {}, h.page.title));
        var from = Math.max(0, h.at - 40);
        a.appendChild(el("small", {}, (from > 0 ? "..." : "") + h.page.text.slice(from, from + 140)));
        results.appendChild(a);
      });
      results.hidden = false;
    });
  }
  input.addEventListener("input", show);
  input.addEventListener("focus", function () { load(); if (input.value) show(); });
  input.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { var first = results.querySelector("a"); if (first) location.href = first.href; }
  });
  document.addEventListener("click", function (e) { if (!document.getElementById("search").contains(e.target)) results.hidden = true; });
  document.addEventListener("keydown", function (e) {
    var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName || "");
    if (e.key === "Escape") { input.value = ""; results.hidden = true; input.blur(); setMenu(false); }
    else if (e.key === "/" && !typing) { e.preventDefault(); input.focus(); }
  });

  // ---- Mermaid diagrams: the copy Skein vendors, loaded where there is one --
  var diagrams = document.querySelectorAll("pre > code.language-mermaid");
  if (diagrams.length) {
    var m = document.createElement("script");
    m.src = script.dataset.mermaid;
    m.onload = function () {
      diagrams.forEach(function (code) {
        var div = el("div", { class: "mermaid" });
        div.textContent = code.textContent;
        code.parentElement.replaceWith(div);
      });
      window.mermaid.initialize({ startOnLoad: false, theme: root.dataset.theme === "dark" ? "dark" : "default" });
      window.mermaid.run();
    };
    document.head.appendChild(m);
  }

  // wide tables scroll inside themselves, not the page
  document.querySelectorAll("article > table").forEach(function (table) {
    var wrap = el("div", { class: "table" });
    table.replaceWith(wrap);
    wrap.appendChild(table);
  });
})();
