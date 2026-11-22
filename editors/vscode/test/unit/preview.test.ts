// Plain Node.js tests of the Markdown preview's plugin (src/previewplugin.ts)

// req: vscode.preview
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { plugin, PreviewCache } from "../../src/previewplugin";

/** A stand-in for markdown-it: the rules added before `normalize` */
function fakeMarkdownIt() {
  const rules: { before: string; name: string; rule: (state: { src: string; env: unknown }) => void }[] = [];
  return { rules, core: { ruler: { before: (before: string, name: string, rule: (state: { src: string; env: unknown }) => void) => rules.push({ before, name, rule }) } } };
}

test("a document skein has rendered is shown as rendered; another is asked for", () => {
  const cache = new PreviewCache();
  const asked: string[] = [];
  const md = plugin(cache, (source) => asked.push(source))(fakeMarkdownIt());
  assert.equal(md.rules.length, 1);
  assert.equal(md.rules[0].before, "normalize");

  // the server's rendering of a text, whatever its line ends
  cache.put("%rule[a.b] A rule.\r\n", '<a id="a.b"></a>**[a.b](#a.b)** A rule.\n');
  const state = { src: "%rule[a.b] A rule.\n", env: {} };
  md.rules[0].rule(state);
  assert.equal(state.src, '<a id="a.b"></a>**[a.b](#a.b)** A rule.\n');
  assert.deepEqual(asked, []);

  // a text not rendered: shown as written, and asked for
  const other = { src: "%rule[a.c] Another.\n", env: {} };
  md.rules[0].rule(other);
  assert.equal(other.src, "%rule[a.c] Another.\n");
  assert.deepEqual(asked, ["%rule[a.c] Another.\n"]);

  cache.clear();
  assert.equal(cache.get("%rule[a.b] A rule.\n"), undefined);
});

test("the preview's style marks unresolved references, and the plugin is declared", () => {
  const root = path.join(__dirname, "..", "..");
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
  assert.equal(manifest.contributes["markdown.markdownItPlugins"], true);
  const [style] = manifest.contributes["markdown.previewStyles"];
  assert.match(fs.readFileSync(path.join(root, style), "utf8"), /\.skein-unresolved/);
});
