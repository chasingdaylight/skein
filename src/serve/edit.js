// skein serve's editing, added to each page it serves: a button to edit
// the page's file, with the problems `skein check` finds as you type; a
// form for each item on the page and for a new item, built from its type.
(function () {
  "use strict";
  var page = decodeURIComponent(location.pathname.replace(/^\//, ""));
  if (page === "" || /\/$/.test(page)) page += "index.html";
  var file = page.replace(/\.html$/, ".md");
  window.skeinEditing = false;

  function api(path, body) {
    var init = { cache: "no-store", headers: { "x-skein": "1" } };
    if (body !== undefined) {
      init.method = "POST";
      init.headers["content-type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    return fetch("/_skein/" + path, init).then(function (r) { return r.json(); });
  }

  function el(tag, attrs, children) {
    var e = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") e.textContent = attrs[k];
      else if (k.slice(0, 2) === "on") e.addEventListener(k.slice(2), attrs[k]);
      else e.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { if (c) e.appendChild(c); });
    return e;
  }

  function debounce(f, ms) {
    var t = null;
    return function () { clearTimeout(t); t = setTimeout(f, ms); };
  }

  var style = el("style", { text:
    ".skein-bar{position:fixed;right:1rem;bottom:1rem;display:flex;flex-wrap:wrap;align-items:center;gap:.5rem;z-index:10}" +
    ".skein-where{font-size:.85rem;padding:.2rem .5rem;border-radius:4px;background:#eee;color:#222}" +
    ".skein-bar button,.skein-panel button{font:inherit;padding:.3rem .8rem;border:1px solid #888;border-radius:4px;background:#fff;color:#222;cursor:pointer}" +
    ".skein-item-edit{font-size:.75em;margin-left:.4em;padding:0 .4em;border:1px solid #aaa;border-radius:3px;background:none;color:inherit;cursor:pointer}" +
    ".skein-panel{position:fixed;top:0;right:0;bottom:0;width:min(42rem,100%);overflow:auto;background:#fafafa;color:#222;border-left:1px solid #888;padding:1rem;z-index:20;box-sizing:border-box}" +
    ".skein-panel textarea{width:100%;min-height:24rem;font-family:monospace;font-size:.9rem;box-sizing:border-box}" +
    ".skein-panel label{display:block;margin:.5rem 0 .1rem;font-weight:600}" +
    ".skein-panel input,.skein-panel select{width:100%;box-sizing:border-box;font:inherit}" +
    ".skein-panel .problems{margin:.5rem 0;padding-left:1.2rem;font-size:.9rem}" +
    ".skein-panel .error{color:#b00020}.skein-panel .warning{color:#8a5a00}.skein-panel .ok{color:#1b5e20}" +
    ".skein-panel .actions{display:flex;gap:.5rem;margin-top:.8rem}" +
    "@media (prefers-color-scheme: dark){.skein-panel{background:#1e1e1e;color:#ddd}.skein-panel .ok{color:#81c784}.skein-panel .error{color:#ef9a9a}.skein-panel .warning{color:#ffcc80}.skein-bar button,.skein-panel button{background:#2a2a2a;color:#ddd}}"
  });
  document.head.appendChild(style);

  var panel = null;
  function open(title, body) {
    close();
    window.skeinEditing = true;
    panel = el("aside", { "class": "skein-panel", "aria-label": title }, [el("h2", { text: title })].concat(body));
    document.body.appendChild(panel);
  }
  function close() {
    if (panel) panel.remove();
    panel = null;
    window.skeinEditing = false;
  }
  function saved() {
    close();
    location.reload();
  }

  // a save, with a change started first when the project's way of saving asks for one
  function store(path, body, problems) {
    api(path, body).then(function (r) {
      if (r.signIn) {
        if (confirm(r.error + ". Sign in now? What you typed here is not kept.")) location.href = "/_skein/sign-in?back=" + encodeURIComponent(location.pathname);
        return showProblems(problems, r);
      }
      if (r.needsChange) {
        var name = prompt(r.error + "\n\nName the change (lowercase letters, digits and dashes):", "");
        if (!name) return showProblems(problems, r);
        return api("change", { action: "start", name: name.trim() }).then(function (c) {
          if (c.error) return showProblems(problems, c);
          store(path, body, problems);
        });
      }
      if (r.error) return showProblems(problems, r);
      if (r.warning) alert(r.warning);
      saved();
    });
  }

  function act(action, name) {
    api("change", { action: action, name: name || "" }).then(function (r) {
      if (r.error) return alert(r.error);
      if (action === "propose") alert(r.said);
      location.reload();
    });
  }

  // where saves go: the branch, or the change checked out, and what can be done with it
  function savingBar(st) {
    var nodes = [];
    if (st.user) nodes.push(el("span", { "class": "skein-where", text: "signed in as " + st.user }));
    if (!st.branch) return nodes.concat([el("span", { "class": "skein-where", text: "not in git: saves are written, not committed" })]);
    if (st.mode === "commit") return nodes.concat([el("span", { "class": "skein-where", text: "saves are committed to " + (st.target || st.branch) })]);
    if (st.change) {
      nodes.push(el("span", { "class": "skein-where", text: "change " + st.change + " (into " + st.target + ")" }));
      if (st.mode === "branch") nodes.push(el("button", { text: "Merge into " + st.target, onclick: function () { if (confirm("Merge the change " + st.change + " into " + st.target + "?")) act("merge", st.change); } }));
      else {
        var propose = el("button", { text: "Propose", onclick: function () { act("propose", st.change); } });
        propose.disabled = !st.forge;
        nodes.push(propose);
      }
      nodes.push(el("button", { text: "Leave", onclick: function () { act("open", ""); } }));
      nodes.push(el("button", { text: "Abandon", onclick: function () { if (confirm("Delete the change " + st.change + ", unmerged?")) act("abandon", st.change); } }));
      return nodes;
    }
    if (st.changes && st.changes.length) {
      var pick = el("select", { "aria-label": "Changes" }, [el("option", { value: "", text: "open a change…" })].concat(st.changes.map(function (c) {
        return el("option", { value: c.name, text: c.name + " (" + c.commits + " commit" + (c.commits === 1 ? "" : "s") + ")" });
      })));
      pick.addEventListener("change", function () { if (pick.value) act("open", pick.value); });
      nodes.push(pick);
    }
    nodes.push(el("button", { text: "Start a change", onclick: function () {
      var name = prompt("Name the change (lowercase letters, digits and dashes):", "");
      if (name) api("change", { action: "start", name: name.trim() }).then(function (r) { if (r.error) alert(r.error); else location.reload(); });
    } }));
    return nodes;
  }

  function showProblems(list, result) {
    list.textContent = "";
    if (result.error) {
      list.appendChild(el("li", { "class": "error", text: result.error }));
      return;
    }
    (result.problems || []).forEach(function (p) {
      list.appendChild(el("li", { "class": p.severity, text: (p.line ? "line " + p.line + ": " : "") + p.message }));
    });
    if (result.elsewhere) list.appendChild(el("li", { "class": "warning", text: result.elsewhere + " in other files" }));
    if (!list.firstChild) list.appendChild(el("li", { "class": "ok", text: "skein check finds no problems here" }));
  }

  function editFile() {
    api("source?file=" + encodeURIComponent(file)).then(function (s) {
      if (s.error) return alert(s.error);
      var problems = el("ul", { "class": "problems" });
      var area = el("textarea", { spellcheck: "true" });
      area.value = s.text;
      var check = debounce(function () {
        api("check", { file: file, text: area.value }).then(function (r) { showProblems(problems, r); });
      }, 400);
      area.addEventListener("input", check);
      var save = el("button", { text: "Save", onclick: function () {
        store("source", { file: file, text: area.value, hash: s.hash }, problems);
      } });
      open("Edit " + file, [area, problems, el("div", { "class": "actions" }, [save, el("button", { text: "Cancel", onclick: close })])]);
      check();
    });
  }

  function field(label, input) {
    return el("div", {}, [el("label", { text: label }), input]);
  }
  function choice(values, value, empty) {
    var s = el("select");
    if (empty) s.appendChild(el("option", { value: "", text: "(none)" }));
    values.forEach(function (v) {
      var o = el("option", { value: v, text: v });
      if (v === value) o.selected = true;
      s.appendChild(o);
    });
    return s;
  }
  var lists = 0;
  function suggested(values, value) {
    var id = "skein-list-" + (lists++);
    var input = el("input", { list: id });
    input.value = value || "";
    var dl = el("datalist", { id: id }, values.map(function (v) { return el("option", { value: v }); }));
    return { input: input, node: el("span", {}, [input, dl]) };
  }

  function editItem(id, typeName) {
    var q = id ? "id=" + encodeURIComponent(id) : (typeName ? "type=" + encodeURIComponent(typeName) : "");
    api("form?" + q).then(function (r) {
      if (r.error) return alert(r.error);
      var f = r.form, item = f.item || { attributes: {}, links: {} }, t = f.type;
      var nodes = [], read = [];
      if (!id) {
        var types = choice(f.types, t.name, false);
        types.addEventListener("change", function () { editItem(null, types.value); });
        nodes.push(field("Type", types));
        var newId = el("input", { placeholder: t.numbered ? "the next number" : "the item's ID" });
        nodes.push(field("ID", newId));
        read.push(function (s) { s.id = newId.value.trim(); s.new = true; });
        if (!f.itemFiles) {
          var doc = choice(f.documents, file, false);
          nodes.push(field("Document it goes at the end of", doc));
          read.push(function (s) { s.document = doc.value; });
        }
        var text = el("textarea", { rows: "6" });
        nodes.push(field("Text", text));
        read.push(function (s) { s.text = text.value; });
      }
      [["Category", "category", t.categories], ["Status", "status", t.statuses], ["Verification", "verification", t.verification]].forEach(function (k) {
        if (!k[2] || !k[2].length) return;
        var s = choice(k[2], item[k[1]] || "", true);
        nodes.push(field(k[0], s));
        read.push(function (out) { out[k[1]] = s.value; });
      });
      t.attributes.forEach(function (a) {
        var v = item.attributes[a.name] || "";
        var label = a.name + (a.required ? " (required)" : "") + (a.list ? ", separated by commas" : "");
        var input, node;
        if (a.values && a.values.length && !a.list) input = choice(a.values, v, true);
        else if (a.kind === "boolean") input = choice(["true", "false"], v, true);
        else if (a.kind === "date") { input = el("input", { type: "date" }); input.value = v; }
        else { var sg = suggested(a.values || [], v); input = sg.input; node = sg.node; }
        nodes.push(field(label, node || input));
        read.push(function (out) { out.attributes[a.name] = input.value.trim(); });
      });
      t.links.forEach(function (l) {
        var sg = suggested(l.targets, (item.links[l.name] || []).join(", "));
        nodes.push(field(l.name + ", IDs separated by commas", sg.node));
        read.push(function (out) {
          out.links[l.name] = sg.input.value.split(",").map(function (x) { return x.trim(); }).filter(function (x) { return x; });
        });
      });
      var problems = el("ul", { "class": "problems" });
      function form() {
        var s = { id: id || "", type: t.name, attributes: {}, links: {} };
        read.forEach(function (fn) { fn(s); });
        return s;
      }
      var check = debounce(function () {
        api("preview", form()).then(function (res) { showProblems(problems, res); });
      }, 400);
      nodes.forEach(function (n) { n.addEventListener("input", check); n.addEventListener("change", check); });
      var save = el("button", { text: "Save", onclick: function () {
        var s = form();
        s.hash = r.hash;
        store("save", s, problems);
      } });
      var actions = [save];
      // an approval of the item as it is, by whoever is signed in
      if (id && t.approval && t.approval.length) {
        var role = t.roles && t.roles.length ? choice(t.roles, "", false) : null;
        if (role) actions.push(role);
        actions.push(el("button", { text: "Approve", onclick: function () {
          store("approve", { id: id, as: role ? role.value : "" }, problems);
        } }));
      }
      actions.push(el("button", { text: "Cancel", onclick: close }));
      open(id ? "Edit " + id : "New " + t.name, nodes.concat([problems, el("div", { "class": "actions" }, actions)]));
      check();
    });
  }

  api("page?file=" + encodeURIComponent(file)).then(function (info) {
    if (info.error) return;
    var bar = el("div", { "class": "skein-bar" });
    if (info.editable) bar.appendChild(el("button", { text: "Edit this file", onclick: editFile }));
    if (info.types && info.types.length) bar.appendChild(el("button", { text: "New item", onclick: function () { editItem(null, info.types[0]); } }));
    if (info.signIn) bar.appendChild(el("a", { "class": "skein-where", href: info.signIn + "?back=" + encodeURIComponent(location.pathname), text: "Sign in to edit" }));
    var first = bar.firstChild;
    if (info.saving) savingBar(info.saving).forEach(function (n) { bar.insertBefore(n, first); });
    document.body.appendChild(bar);
    (info.items || []).forEach(function (it) {
      var at = it.inDocument ? document.getElementById(it.id) : document.querySelector("h1");
      if (!at) return;
      var where = it.inDocument && at.nextElementSibling ? at.nextElementSibling : at;
      where.appendChild(el("button", { "class": "skein-item-edit", title: "Edit " + it.id, text: "edit", onclick: function (e) { e.preventDefault(); editItem(it.id); } }));
    });
  });
})();
