// Plain Node.js tests of the pages of the trace and coverage views (src/page.ts)

// req: vscode.views
import * as assert from "node:assert/strict";
import { test } from "node:test";
import { page, parseLink } from "../../src/page";

test("the links of a page: items, places in files, and the web", () => {
  assert.deepEqual(parseLink("skein:item/lex.token"), { kind: "item", id: "lex.token" });
  assert.deepEqual(parseLink("skein:file/spec/lex.md#12"), { kind: "file", file: "spec/lex.md", line: 12 });
  assert.deepEqual(parseLink("skein:file/spec/lex.md"), { kind: "file", file: "spec/lex.md", line: 1 });
  assert.deepEqual(parseLink("https://example.org/a"), { kind: "external", href: "https://example.org/a" });
  assert.equal(parseLink("javascript:alert(1)"), undefined);
  assert.equal(parseLink("skein:item/"), undefined);
});

test("a page: the theme's colors and fonts, a script only by its nonce", () => {
  const html = page("Trace: <x>", "<h1>x</h1>", "N0NCE");
  assert.match(html, /script-src 'nonce-N0NCE'/);
  assert.match(html, /<script nonce="N0NCE">/);
  assert.match(html, /var\(--vscode-font-family\)/);
  assert.match(html, /var\(--vscode-editor-font-family\)/);
  assert.match(html, /<title>Trace: &lt;x&gt;<\/title>/);
  assert.match(html, /<h1>x<\/h1>/);
});
