// Plain Node.js tests of which project a file is in (src/projectmodel.ts)

// req: vscode.projects
import * as assert from "node:assert/strict";
import { test } from "node:test";
import { labelOf, parseTemplates, ProjectInfo, projectOf } from "../../src/projectmodel";

const projects: ProjectInfo[] = [
  { name: "outer", uri: "file:///C:/work" },
  { name: "inner", uri: "file:///C:/work/cesium-src" },
  { name: "skein", uri: "file:///C:/scratch/skein" },
];

test("a file is in the project nearest above it", () => {
  assert.equal(projectOf(projects, "file:///C:/work/cesium-src/spec/a.md", true)?.name, "inner");
  assert.equal(projectOf(projects, "file:///C:/work/readme.md", true)?.name, "outer");
  assert.equal(projectOf(projects, "file:///C:/work/cesium-src-old/a.md", true)?.name, "outer");
  assert.equal(projectOf(projects, "file:///D:/elsewhere/a.md", true), undefined);
});

test("VS Code's way of writing a Windows URI matches the server's, where case does not count", () => {
  assert.equal(projectOf(projects, "file:///c%3A/scratch/skein/docs/x.md", true)?.name, "skein");
  assert.equal(projectOf(projects, "file:///c%3A/scratch/skein/docs/x.md", false), undefined);
});

test("two projects of one name are told apart by their folders", () => {
  const two: ProjectInfo[] = [
    { name: "spec", uri: "file:///a/one" },
    { name: "spec", uri: "file:///a/two" },
    { name: "other", uri: "file:///a/three" },
  ];
  assert.equal(labelOf(two, two[0]), "spec (one)");
  assert.equal(labelOf(two, two[2]), "other");
});

// req: vscode.discoverable
test("the templates skein lists, for Initialize a Project", () => {
  const listed = "langspec  The specification of a programming language\nnpr7150.2d  Software work under NPR 7150.2D, as the handbook reads it\n\n";
  assert.deepEqual(parseTemplates(listed), [
    { name: "langspec", description: "The specification of a programming language" },
    { name: "npr7150.2d", description: "Software work under NPR 7150.2D, as the handbook reads it" },
  ]);
});
