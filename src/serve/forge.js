// The static site's edit mode, saving through the project's forge (#283):
// the files changed in this browser (static.js) go to the forge as a change
// proposed in a pull request (`[serve] save = "pull-request"` or "branch"),
// or as a commit on the branch (`save = "commit"`), through the forge's
// API, as the person editing, with a token they give, kept for this
// browser's session only. GitHub's sign-in cannot be done from a page
// alone (its token endpoints answer no other site), so it is a token for
// every forge.
(function (global) {
  "use strict";

  function Failed(message, status) { this.message = message; this.status = status; }

  function request(method, url, headers, body) {
    var init = { method: method, headers: Object.assign({}, headers) };
    if (body !== undefined) {
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    return global.fetch(url, init).then(function (r) {
      return r.text().then(function (text) {
        var json = null;
        try { json = text ? JSON.parse(text) : null; } catch (e) { json = null; }
        if (!r.ok) throw new Failed((json && (json.message || json.error)) || ("the forge answered " + r.status), r.status);
        return json;
      });
    });
  }

  function b64(text) {
    var bytes = new TextEncoder().encode(text), s = "";
    for (var i = 0; i < bytes.length; i += 32768) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
    return btoa(s);
  }

  function enc(path) { return path.split("/").map(encodeURIComponent).join("/"); }

  // each forge: the branch changes go to when none is given, and the save
  var forges = {
    github: {
      headers: function (t) { return { Authorization: "Bearer " + t, Accept: "application/vnd.github+json" }; },
      defaultBranch: function (cfg, h) {
        return request("GET", cfg.api + "/repos/" + cfg.repository, h).then(function (r) { return r.default_branch; });
      },
      save: function (cfg, h, branch, name, changes, message) {
        var repo = cfg.api + "/repos/" + cfg.repository;
        var head;
        return request("GET", repo + "/git/ref/heads/" + enc(branch), h).then(function (ref) {
          head = ref.object.sha;
          return request("GET", repo + "/git/commits/" + head, h);
        }).then(function (commit) {
          return request("POST", repo + "/git/trees", h, {
            base_tree: commit.tree.sha,
            tree: changes.map(function (c) {
              return c.kind === "delete" ? { path: c.path, mode: "100644", type: "blob", sha: null } : { path: c.path, mode: "100644", type: "blob", content: c.content };
            }),
          });
        }).then(function (tree) {
          return request("POST", repo + "/git/commits", h, { message: message, tree: tree.sha, parents: [head] });
        }).then(function (made) {
          if (!name) return request("PATCH", repo + "/git/refs/heads/" + enc(branch), h, { sha: made.sha }).then(function () { return made.html_url; });
          return request("POST", repo + "/git/refs", h, { ref: "refs/heads/edit/" + name, sha: made.sha }).then(function () {
            return request("POST", repo + "/pulls", h, { title: "Change " + name, head: "edit/" + name, base: branch, body: "Proposed from the project's site, with skein." });
          }).then(function (pr) { return pr.html_url; });
        });
      },
    },
    gitlab: {
      headers: function (t) { return { Authorization: "Bearer " + t }; },
      project: function (cfg) { return cfg.api + "/projects/" + encodeURIComponent(cfg.repository); },
      defaultBranch: function (cfg, h) {
        return request("GET", this.project(cfg), h).then(function (r) { return r.default_branch; });
      },
      save: function (cfg, h, branch, name, changes, message) {
        var project = this.project(cfg);
        var body = {
          branch: name ? "edit/" + name : branch,
          commit_message: message,
          actions: changes.map(function (c) {
            var a = { action: c.kind, file_path: c.path };
            if (c.kind !== "delete") a.content = c.content;
            return a;
          }),
        };
        if (name) body.start_branch = branch;
        return request("POST", project + "/repository/commits", h, body).then(function (commit) {
          if (!name) return commit.web_url;
          return request("POST", project + "/merge_requests", h, { source_branch: "edit/" + name, target_branch: branch, title: "Change " + name, description: "Proposed from the project's site, with skein." }).then(function (mr) { return mr.web_url; });
        });
      },
    },
    forgejo: {
      headers: function (t) { return { Authorization: "token " + t }; },
      defaultBranch: function (cfg, h) {
        return request("GET", cfg.api + "/repos/" + cfg.repository, h).then(function (r) { return r.default_branch; });
      },
      save: function (cfg, h, branch, name, changes, message) {
        var repo = cfg.api + "/repos/" + cfg.repository;
        // a file changed or removed is named by what it is now
        return Promise.all(changes.map(function (c) {
          if (c.kind === "create") return Promise.resolve({ operation: "create", path: c.path, content: b64(c.content) });
          return request("GET", repo + "/contents/" + enc(c.path) + "?ref=" + encodeURIComponent(branch), h).then(function (f) {
            var file = { operation: c.kind, path: c.path, sha: f.sha };
            if (c.kind !== "delete") file.content = b64(c.content);
            return file;
          });
        })).then(function (files) {
          var body = { branch: branch, message: message, files: files };
          if (name) body.new_branch = "edit/" + name;
          return request("POST", repo + "/contents", h, body);
        }).then(function (done) {
          if (!name) return done && done.commit ? done.commit.html_url : "";
          return request("POST", repo + "/pulls", h, { title: "Change " + name, head: "edit/" + name, base: branch, body: "Proposed from the project's site, with skein." }).then(function (pr) { return pr.html_url; });
        });
      },
    },
  };

  /// Saves `edits` (path -> text, or null for a file removed) through the
  /// forge `cfg` with `token`, under the change `name` (null: a commit on
  /// the branch); `originals` the files as the site has them. The address
  /// of the pull request or the commit.
  function saveEdits(cfg, token, edits, originals, name) {
    var f = forges[cfg.kind];
    if (!f) return Promise.reject(new Failed("skein cannot save to a forge of the kind " + cfg.kind));
    var h = f.headers(token);
    var paths = Object.keys(edits);
    var changes = paths.map(function (p) {
      return { path: cfg.prefix + p, content: edits[p], kind: edits[p] === null ? "delete" : Object.prototype.hasOwnProperty.call(originals, p) ? "update" : "create" };
    });
    var message = name ? "Change " + name : "Edit " + paths.join(", ");
    return (cfg.branch ? Promise.resolve(cfg.branch) : f.defaultBranch(cfg, h)).then(function (branch) {
      return f.save(cfg, h, branch, name, changes, message);
    });
  }

  global.SkeinForge = { save: saveEdits, Failed: Failed };

  // in a page: the button beside the changed files
  if (typeof document === "undefined" || !document.currentScript) return;
  var me = document.currentScript.src;
  var base = me.slice(0, me.lastIndexOf("_skein/"));
  var tokenKey = "skein-forge-token:" + base;
  var config = fetch(base + "_skein/forge.json").then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  var originals = fetch(base + "_skein/files.json").then(function (r) { return r.json(); });
  var where = {
    github: "a fine-grained personal access token for REPO with Contents and Pull requests, read and write (WEB/settings/personal-access-tokens)",
    gitlab: "a personal access token with the api scope (WEB/-/user_settings/personal_access_tokens)",
    forgejo: "an access token with write:repository (WEB/user/settings/applications)",
  };

  global.skeinStaticActions = function (bar, edits) {
    config.then(function (cfg) {
      if (!cfg) return;
      var button = document.createElement("button");
      button.textContent = cfg.save === "commit" ? "Commit them to " + (cfg.branch || "the default branch") : "Propose them on " + cfg.kind;
      button.onclick = function () {
        var name = null;
        if (cfg.save !== "commit") {
          name = (prompt("Name the change (lowercase letters, digits and dashes):", "") || "").trim();
          if (!name) return;
          if (!/^[a-z0-9][a-z0-9-]{0,59}$/.test(name)) return alert("A change is named in lowercase letters, digits and dashes, as fix-lexing.");
        }
        var token = sessionStorage.getItem(tokenKey);
        if (!token) {
          token = (prompt("To save on " + cfg.kind + ", give " + where[cfg.kind].replace("REPO", cfg.repository).replace("WEB", cfg.url) + ". It is kept for this browser session only.", "") || "").trim();
          if (!token) return;
          sessionStorage.setItem(tokenKey, token);
        }
        button.disabled = true;
        originals.then(function (orig) {
          return saveEdits(cfg, token, edits, orig, name);
        }).then(function (url) {
          if (global.skeinDiscard) global.skeinDiscard();
          if (confirm((name ? "Proposed: " : "Committed: ") + url + "\n\nOpen it?")) location.href = url; else location.reload();
        }).catch(function (e) {
          if (e.status === 401 || e.status === 403) sessionStorage.removeItem(tokenKey);
          alert("Not saved on " + cfg.kind + ": " + e.message);
          button.disabled = false;
        });
      };
      bar.insertBefore(button, bar.lastChild);
    });
  };
})(typeof window !== "undefined" ? window : globalThis);
