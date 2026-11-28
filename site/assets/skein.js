// What Skein's pages have that cesiumlang.org's do not: screenshots that
// follow the light and dark toggle, and Mermaid diagrams.
(function () {
  "use strict";

  var root = document.documentElement;
  var script = document.currentScript;

  // A screenshot is a <picture> with a dark source for
  // (prefers-color-scheme: dark), which GitHub shows by the reader's system;
  // here it follows the toggle (explorer.js sets data-theme).
  var pictures = [];
  document.querySelectorAll(".content picture source[media*='prefers-color-scheme']").forEach(function (s) {
    pictures.push({ source: s, dark: /dark/.test(s.getAttribute("media")) });
  });
  function follow() {
    var dark = root.dataset.theme === "dark";
    pictures.forEach(function (p) { p.source.media = p.dark === dark ? "all" : "not all"; });
  }
  follow();
  new MutationObserver(follow).observe(root, { attributes: true, attributeFilter: ["data-theme"] });

  // Mermaid diagrams: the copy Skein vendors, loaded where there is one
  var diagrams = document.querySelectorAll(".content pre > code.language-mermaid");
  if (diagrams.length) {
    var m = document.createElement("script");
    m.src = script.dataset.mermaid;
    m.onload = function () {
      diagrams.forEach(function (code) {
        var div = document.createElement("div");
        div.className = "mermaid";
        div.textContent = code.textContent;
        code.parentElement.replaceWith(div);
      });
      window.mermaid.initialize({ startOnLoad: false, theme: root.dataset.theme === "dark" ? "dark" : "default" });
      window.mermaid.run();
    };
    document.head.appendChild(m);
  }
})();
