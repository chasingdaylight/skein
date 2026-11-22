// Plain Node.js tests of the graph view's model (src/graphmodel.ts)

// req: vscode.graph
import * as assert from "node:assert/strict";
import { test } from "node:test";
import { filter, GraphNode, layout, Network, noFilters, search } from "../../src/graphmodel";

function node(id: string, extra: Partial<GraphNode> = {}): GraphNode {
  return { id, type: "rule", status: "draft", title: "", uri: "", line: 0, source: "spec", profiles: [], repository: "", ...extra };
}

const net: Network = {
  nodes: [
    node("r.a", { title: "Line comments" }),
    node("r.b", { title: "Block comments", profiles: ["core"] }),
    node("t.one", { type: "test", source: "tests" }),
    node("t.two", { type: "test", source: "tests" }),
    node("other:x.y", { type: "", repository: "other" }),
  ],
  edges: [
    { from: "t.one", to: "r.a", type: "verifies", state: "reviewed" },
    { from: "t.two", to: "r.b", type: "verifies", state: "suspect" },
    { from: "r.b", to: "other:x.y", type: "derives", state: "" },
  ],
  types: ["rule", "test"],
  links: ["verifies", "derives"],
  profiles: ["core"],
  sources: ["spec", "tests"],
};

test("layers: an item above the items that link to it, ordered under them", () => {
  const places = layout(net.nodes, net.edges);
  assert.equal(places.get("other:x.y")!.layer, 0);
  assert.equal(places.get("r.a")!.layer, 0);
  assert.equal(places.get("r.b")!.layer, 1);
  assert.equal(places.get("t.one")!.layer, 1);
  assert.equal(places.get("t.two")!.layer, 2);
  // a loop of links does not hang the layout
  const loop = layout([node("a"), node("b")], [{ from: "a", to: "b", type: "x", state: "" }, { from: "b", to: "a", type: "x", state: "" }]);
  assert.equal(loop.size, 2);
});

test("filters: item types, link types, profiles, sources, other repositories", () => {
  assert.equal(filter(net, noFilters).nodes.length, 5);
  const tests = filter(net, { ...noFilters, types: ["test"], others: false });
  assert.deepEqual(tests.nodes.map((n) => n.id), ["t.one", "t.two"]);
  assert.equal(tests.edges.length, 0);
  assert.deepEqual(filter(net, { ...noFilters, profile: "core" }).nodes.map((n) => n.id), ["r.b", "other:x.y"]);
  assert.deepEqual(filter(net, { ...noFilters, links: ["derives"] }).edges.map((e) => e.to), ["other:x.y"]);
  assert.deepEqual(filter(net, { ...noFilters, source: "tests", others: false }).nodes.map((n) => n.id), ["t.one", "t.two"]);
});

test("search: every word, in the ID or the title, in any case", () => {
  assert.deepEqual([...search(net.nodes, "comments BLOCK")], ["r.b"]);
  assert.deepEqual([...search(net.nodes, "t.")].sort(), ["t.one", "t.two"]);
  assert.equal(search(net.nodes, "  ").size, 0);
});
