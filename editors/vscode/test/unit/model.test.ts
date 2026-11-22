// Plain Node.js tests of the tree of items and the status bar's text (src/model.ts)

// req: vscode.tree, vscode.status
import * as assert from "node:assert/strict";
import { test } from "node:test";
import { buildTree, coverageText, describe, ItemInfo, Node } from "../../src/model";

function item(id: string, file: string, source: string, extra: Partial<ItemInfo> = {}): ItemInfo {
  return { id, type: "rule", status: "draft", uri: `file:///p/${file}`, file, line: 0, title: "", source, removed: false, ...extra };
}

function labels(nodes: Node[]): string[] {
  return nodes.map((n) => (n.kind === "source" ? n.path : n.kind === "file" ? n.label : n.item.id));
}

test("one source: its files at the top, each with its items, parts under their whole", () => {
  const roots = buildTree({
    project: "p",
    sources: ["spec"],
    items: [
      item("lex.b", "spec/lex.md", "spec"),
      item("lex.b.as", "spec/lex.md", "spec", { parent: "lex.b" }),
      item("a.one", "spec/a.md", "spec"),
    ],
  });
  assert.deepEqual(labels(roots), ["a.md", "lex.md"]);
  const lex = roots[1];
  assert.deepEqual(labels(lex.children), ["lex.b"]);
  assert.deepEqual(labels(lex.children[0].children), ["lex.b.as"]);
});

test("several sources: the sources at the top, in the project's order", () => {
  const roots = buildTree({
    project: "p",
    sources: ["spec", "needs"],
    items: [item("r.1", "needs/r.1.md", "needs"), item("lex.a", "spec/lex.md", "spec")],
  });
  assert.deepEqual(labels(roots), ["spec", "needs"]);
  assert.deepEqual(labels(roots[1].children), ["r.1.md"]);
});

test("a part in another file than its whole is under its own file", () => {
  const roots = buildTree({
    project: "p",
    sources: ["spec"],
    items: [item("w", "spec/w.md", "spec"), item("w.p", "spec/p.md", "spec", { parent: "w" })],
  });
  assert.deepEqual(labels(roots), ["p.md", "w.md"]);
});

test("describe and coverageText", () => {
  assert.equal(describe(item("x", "f.md", "", { category: "syntax" })), "rule, syntax, draft");
  assert.equal(describe(item("x", "f.md", "")), "rule, draft");
  assert.equal(coverageText(2, 3).text, "$(checklist) 66%");
  assert.equal(coverageText(2, 3).tooltip, "skein: 2 of 3 expected links and citations are there");
  assert.equal(coverageText(0, 0).tooltip, "skein: nothing is expected");
});
