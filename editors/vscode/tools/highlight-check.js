// How VS Code highlights skein's markers and references: tokenizes Markdown
// files with VS Code's own Markdown grammar and the extension's injection, as
// the editor does, and prints the color each built-in theme gives each skein
// scope (DUMP=1: every token of the lines with a %, instead).
//
// It runs in VS Code's Electron as Node, which reads the tokenizer from VS
// Code's own node_modules.asar, so nothing is installed:
//
//   VSCODE_APP=".../Microsoft VS Code/<commit>/resources/app" ELECTRON_RUN_AS_NODE=1 \
//     ".../Microsoft VS Code/Code.exe" tools/highlight-check.js syntaxes/skein.injection.tmLanguage.json FILE.md...
const fs = require("fs");
const path = require("path");
const APP = process.env.VSCODE_APP;
if (!APP) { console.error("set VSCODE_APP to VS Code's resources/app directory"); process.exit(2); }
const tm = require(APP + "/node_modules.asar/vscode-textmate");
const onig = require(APP + "/node_modules.asar/vscode-oniguruma");

const [injectionPath, ...files] = process.argv.slice(2);
const wasm = fs.readFileSync(APP + "/node_modules.asar/vscode-oniguruma/release/onig.wasm").buffer;

const themeFiles = {
  "Dark Modern": "theme-defaults/themes/dark_modern.json",
  "Light Modern": "theme-defaults/themes/light_modern.json",
  "Dark+": "theme-defaults/themes/dark_plus.json",
  "Light+": "theme-defaults/themes/light_plus.json",
  "Monokai": "theme-monokai/themes/monokai-color-theme.json",
  "Solarized Dark": "theme-solarized-dark/themes/solarized-dark-color-theme.json",
  "Solarized Light": "theme-solarized-light/themes/solarized-light-color-theme.json",
  "Quiet Light": "theme-quietlight/themes/quietlight-color-theme.json",
  "Abyss": "theme-abyss/themes/abyss-color-theme.json",
  "Kimbie Dark": "theme-kimbie-dark/themes/kimbie-dark-color-theme.json",
  "Tomorrow Night Blue": "theme-tomorrow-night-blue/themes/tomorrow-night-blue-color-theme.json",
  "Red": "theme-red/themes/Red-color-theme.json",
};

// JSON with comments and trailing commas
function readJsonc(file) {
  const text = fs.readFileSync(file, "utf8");
  let out = "", i = 0, inStr = false;
  while (i < text.length) {
    const c = text[i];
    if (inStr) { out += c; if (c === "\\") { out += text[i + 1]; i += 2; continue; } if (c === '"') inStr = false; i++; continue; }
    if (c === '"') { inStr = true; out += c; i++; continue; }
    if (c === "/" && text[i + 1] === "/") { while (i < text.length && text[i] !== "\n") i++; continue; }
    if (c === "/" && text[i + 1] === "*") { i = text.indexOf("*/", i + 2) + 2; continue; }
    out += c; i++;
  }
  return JSON.parse(out.replace(/,(\s*[}\]])/g, "$1"));
}

// a theme's token rules, following "include"
function themeRules(file) {
  const t = readJsonc(file);
  let rules = [];
  if (t.include) rules = themeRules(path.join(path.dirname(file), t.include));
  for (const r of t.tokenColors || []) {
    const scopes = typeof r.scope === "string" ? r.scope.split(",") : r.scope || [];
    for (const s of scopes) rules.push({ selector: s.trim(), fg: r.settings.foreground, style: r.settings.fontStyle });
  }
  return rules;
}

// does a selector ("a b", "a.b") match the scope stack? the most specific wins
// TextMate: the last part matches some scope of the stack (deeper is more
// specific), and the earlier parts match scopes above it, in order
function matchScore(selector, stack) {
  const parts = selector.split(/\s+/).filter(Boolean);
  const hit = (s, q) => s === q || s.startsWith(q + ".");
  for (let i = stack.length - 1; i >= 0; i--) {
    const last = parts[parts.length - 1];
    if (!hit(stack[i], last)) continue;
    let j = i - 1, ok = true;
    for (let p = parts.length - 2; p >= 0; p--) {
      while (j >= 0 && !hit(stack[j], parts[p])) j--;
      if (j < 0) { ok = false; break; }
      j--;
    }
    if (ok) return i * 1000 + last.split(".").length * 10 + parts.length;
  }
  return 0;
}

function colorOf(rules, stack) {
  let fg = null, fgScore = 0, st = null, stScore = 0;
  for (const r of rules) {
    const s = matchScore(r.selector, stack);
    if (r.fg && s > fgScore) { fgScore = s; fg = r; }
    if (r.style !== undefined && s > stScore) { stScore = s; st = r; }
  }
  if (!fg && !st) return "-";
  return `${fg ? fg.fg + " (" + fg.selector + ")" : "default"}${st && st.style ? "  " + st.style + " (" + st.selector + ")" : ""}`;
}

(async () => {
  await onig.loadWASM(wasm);
  const registry = new tm.Registry({
    onigLib: Promise.resolve({ createOnigScanner: (s) => new onig.OnigScanner(s), createOnigString: (s) => new onig.OnigString(s) }),
    loadGrammar: async (scope) => {
      if (scope === "text.html.markdown") return tm.parseRawGrammar(fs.readFileSync(APP + "/extensions/markdown-basics/syntaxes/markdown.tmLanguage.json", "utf8"), "markdown.json");
      if (scope === "skein.injection") return tm.parseRawGrammar(fs.readFileSync(injectionPath, "utf8"), "skein.json");
      return null;
    },
    getInjections: (scope) => (scope === "text.html.markdown" ? ["skein.injection"] : []),
  });
  const grammar = await registry.loadGrammar("text.html.markdown");
  const themes = Object.fromEntries(Object.entries(themeFiles).map(([n, f]) => [n, themeRules(APP + "/extensions/" + f)]));

  const seen = new Map(); // innermost skein scope -> { stack, example }
  for (const file of files) {
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    let state = tm.INITIAL;
    lines.forEach((line, n) => {
      const r = grammar.tokenizeLine(line, state);
      state = r.ruleStack;
      const toks = r.tokens.map((t) => ({ text: line.slice(t.startIndex, t.endIndex), scopes: t.scopes }));
      if (process.env.DUMP && line.includes("%")) {
        console.log(`${path.basename(file)}:${n + 1}: ${line.slice(0, 100)}`);
        for (const t of toks) if (t.text.trim()) console.log(`    ${JSON.stringify(t.text).padEnd(34)} ${t.scopes.slice(1).join(" ")}`);
      }
      for (const t of toks) {
        const sk = t.scopes.filter((s) => s.endsWith(".skein"));
        if (!sk.length) continue;
        const key = t.scopes[t.scopes.length - 1];
        if (!seen.has(key)) seen.set(key, { stack: t.scopes, text: t.text, at: `${path.basename(file)}:${n + 1}` });
      }
    });
  }
  if (process.env.DUMP) return;
  for (const [key, v] of seen) {
    console.log(`\n${key}   e.g. ${JSON.stringify(v.text)} at ${v.at}`);
    for (const [name, rules] of Object.entries(themes)) console.log(`  ${name.padEnd(20)} ${colorOf(rules, v.stack)}`);
  }
})();
