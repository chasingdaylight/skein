// Plain Node.js tests of the item form's model (src/formmodel.ts)

// req: vscode.forms
import * as assert from "node:assert/strict";
import { test } from "node:test";
import { Form, ids, initial, problems, toSave } from "../../src/formmodel";

const type = {
  name: "rule",
  description: "",
  categories: ["syntax", "legality"],
  statuses: ["draft", "approved"],
  attributes: [
    { name: "stage", kind: "string" as const, values: ["s0", "s1"], required: true, list: false },
    { name: "classes", kind: "string" as const, values: [], required: false, list: true },
  ],
  links: [{ name: "refines", targets: ["REQ-001", "REQ-002"] }],
  verification: [],
  numbered: false,
};

const editing: Form = {
  item: { id: "lex.a", type: "rule", file: "spec/lex.md", category: "syntax", attributes: { stage: "s0" }, links: { refines: ["REQ-001"] }, text: "A." },
  types: ["rule"],
  type,
  itemFiles: false,
  documents: ["spec/lex.md"],
};

test("a form starts from the item's values", () => {
  const v = initial(editing);
  assert.equal(v.id, "lex.a");
  assert.equal(v.category, "syntax");
  assert.equal(v.status, "");
  assert.equal(v.attributes.stage, "s0");
  assert.equal(v.attributes.classes, "");
  assert.equal(v.links.refines, "REQ-001");
});

test("what is sent: every attribute and link type, lists split, empty values to take out", () => {
  const v = initial(editing);
  v.links.refines = "REQ-001, REQ-002";
  v.attributes.classes = "A B, C";
  v.attributes.stage = "";
  const save = toSave(editing, v);
  assert.equal(save.new, false);
  assert.deepEqual(save.links, { refines: ["REQ-001", "REQ-002"] });
  assert.deepEqual(save.attributes, { stage: "", classes: "A,B,C" });
  assert.equal(save.document, "");
  assert.deepEqual(ids(" a, b  c,,"), ["a", "b", "c"]);
});

test("what is wrong before sending: a required attribute, a new item with no ID or place", () => {
  const v = initial(editing);
  v.attributes.stage = " ";
  assert.deepEqual(problems(editing, v), ["stage is required"]);
  const fresh: Form = { ...editing, item: null, documents: [] };
  const nv = initial(fresh);
  nv.attributes.stage = "s1";
  assert.deepEqual(problems(fresh, nv), ["choose the document the item goes in", "give the item an ID"]);
  assert.equal(toSave(fresh, nv).new, true);
});
