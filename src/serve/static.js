// The static site's edit mode (`skein render --format html --edit`): skein
// built for WebAssembly, run in the page (wasi.js) over the project's files
// (`_skein/files.json`), answers the editing requests skein serve answers
// (`skein api`), for edit.js. What is saved stays in this browser until it
// is downloaded (or, where the site names its forge, proposed there).
(function () {
  "use strict";
  var me = document.currentScript.src;
  var base = me.slice(0, me.lastIndexOf("_skein/"));
  var key = "skein-edits:" + base;
  var page = decodeURIComponent(location.href.slice(base.length).split(/[?#]/)[0]);
  if (page === "" || /\/$/.test(page)) page += "index.html";
  window.skeinStatic = true;
  window.skeinPage = page;

  var enc = new TextEncoder(), dec = new TextDecoder();
  var saved = function () {
    try { return JSON.parse(localStorage.getItem(key) || "{}"); } catch (e) { return {}; }
  };
  var ready = Promise.all([
    fetch(base + "_skein/files.json").then(function (r) { return r.json(); }),
    fetch(base + "_skein/skein.wasm").then(function (r) { return r.arrayBuffer(); }).then(function (b) { return WebAssembly.compile(b); }),
  ]).then(function (got) {
    var files = got[0], edits = saved();
    Object.keys(edits).forEach(function (p) {
      if (edits[p] === null) delete files[p]; else files[p] = edits[p];
    });
    var bytes = {};
    Object.keys(files).forEach(function (p) { bytes[p] = enc.encode(files[p]); });
    return { fs: new SkeinWasi.Files(bytes), module: got[1] };
  });

  // one request, answered by skein in the page
  window.skeinApi = function (path, body) {
    return ready.then(function (s) {
      var parts = path.split("?");
      return SkeinWasi.run(s.module, s.fs, ["skein", "api", body === undefined ? "GET" : "POST", parts[0], parts[1] || ""], enc.encode(body === undefined ? "" : JSON.stringify(body))).then(function (r) {
        // what was written is kept in this browser
        if (s.fs.changed.size) {
          var edits = saved();
          s.fs.changed.forEach(function (p) { edits[p] = s.fs.files.has(p) ? dec.decode(s.fs.files.get(p)) : null; });
          localStorage.setItem(key, JSON.stringify(edits));
          s.fs.changed.clear();
          showChanged();
        }
        if (!r.stdout.trim()) return { error: r.stderr.trim() || "skein stopped (" + r.code + ")" };
        return JSON.parse(r.stdout);
      });
    });
  };

  // the files changed in this browser: to download, or to discard
  var bar = null;
  function showChanged() {
    var edits = saved(), names = Object.keys(edits);
    if (bar) bar.remove();
    bar = null;
    if (!names.length) return;
    bar = document.createElement("div");
    bar.className = "skein-changed";
    bar.style.cssText = "position:fixed;left:1rem;bottom:1rem;max-width:32rem;padding:.6rem .8rem;border:1px solid #888;border-radius:4px;background:#fff;color:#222;z-index:10;font-size:.9rem";
    var title = document.createElement("div");
    title.textContent = names.length + " file" + (names.length === 1 ? "" : "s") + " changed in this browser, not saved anywhere else:";
    bar.appendChild(title);
    names.forEach(function (n) {
      var a = document.createElement("a");
      a.textContent = n + (edits[n] === null ? " (removed)" : "");
      a.style.display = "block";
      if (edits[n] !== null) {
        a.href = URL.createObjectURL(new Blob([edits[n]], { type: "text/markdown" }));
        a.download = n.split("/").pop();
      }
      bar.appendChild(a);
    });
    var discard = document.createElement("button");
    discard.textContent = "Discard them";
    discard.onclick = function () {
      if (!confirm("Forget the changes made in this browser?")) return;
      localStorage.removeItem(key);
      location.reload();
    };
    bar.appendChild(discard);
    if (window.skeinStaticActions) window.skeinStaticActions(bar, edits);
    document.body.appendChild(bar);
  }
  window.skeinChanged = showChanged;
  window.skeinEdits = saved;
  window.skeinDiscard = function () { localStorage.removeItem(key); };
  document.addEventListener("DOMContentLoaded", showChanged);
  if (document.readyState !== "loading") showChanged();
})();
