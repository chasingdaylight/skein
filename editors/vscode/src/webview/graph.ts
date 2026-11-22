// The graph view's page: the network of items in layers, panned by
// dragging and zoomed with the wheel; a search, and filters by item type,
// link type, profile, source and other repositories; a node chosen shows
// its trace beside the graph, with its actions, which its context menu
// has too. Bundled on its own into dist/graph.js.

import { filter, Filters, GraphEdge, GraphNode, layout, Network, noFilters, search } from "../graphmodel";

declare function acquireVsCodeApi(): { postMessage(message: unknown): void; getState(): unknown; setState(state: unknown): void };

const vscode = acquireVsCodeApi();
const svgNs = "http://www.w3.org/2000/svg";
const nodeWidth = 150;
const nodeHeight = 26;
const columnGap = 30;
const layerGap = 70;
const palette = ["--vscode-charts-blue", "--vscode-charts-green", "--vscode-charts-orange", "--vscode-charts-purple", "--vscode-charts-yellow", "--vscode-charts-red"];

let net: Network | undefined;
let filters: Filters = (vscode.getState() as { filters?: Filters } | undefined)?.filters ?? { ...noFilters };
let query = "";
let selected: string | undefined;
let view = { x: 20, y: 20, scale: 1 };

window.addEventListener("message", (event: MessageEvent) => {
  const m = event.data as { kind: string; network?: Network; id?: string; html?: string };
  if (m.kind === "data" && m.network) {
    net = m.network;
    draw();
  }
  if (m.kind === "details" && m.id === selected) details(m.html ?? "");
});
vscode.postMessage({ kind: "ready" });
document.addEventListener("click", () => closeMenu());

function draw(): void {
  const root = document.getElementById("root")!;
  root.textContent = "";
  if (!net) return;
  root.append(controls(net));
  const main = el("div", "main");
  const canvas = el("div", "canvas");
  main.append(canvas, el("div", "details"));
  root.append(main);
  chart(canvas, net);
  if (selected) vscode.postMessage({ kind: "select", id: selected });
}

function controls(n: Network): HTMLElement {
  const bar = el("div", "controls");
  const box = document.createElement("input");
  box.type = "search";
  box.placeholder = "Search items";
  box.value = query;
  box.addEventListener("input", () => {
    query = box.value;
    const canvas = document.querySelector(".canvas") as HTMLElement;
    chart(canvas, n);
  });
  bar.append(box);
  bar.append(choose("Types", n.types, "types"));
  bar.append(choose("Links", n.links, "links"));
  if (n.profiles.length > 0) bar.append(pick("Profile", n.profiles, filters.profile, (v) => set({ profile: v })));
  if (n.sources.length > 1) bar.append(pick("Source", n.sources, filters.source, (v) => set({ source: v })));
  if (n.nodes.some((x) => x.repository)) {
    const label = el("label", "");
    const check = document.createElement("input");
    check.type = "checkbox";
    check.checked = filters.others;
    check.addEventListener("change", () => set({ others: check.checked }));
    label.append(check, " Other repositories");
    bar.append(label);
  }
  return bar;
}

/** Changes the filters and draws the chart again; the controls stay as they are, open or not */
function set(change: Partial<Filters>): void {
  filters = { ...filters, ...change };
  vscode.setState({ filters });
  const canvas = document.querySelector(".canvas") as HTMLElement | null;
  if (canvas && net) chart(canvas, net);
}

/** A drop-down of checkboxes, which stays open while they are checked; none checked is all */
function choose(name: string, all: string[], key: "types" | "links"): HTMLElement {
  const d = document.createElement("details");
  d.className = "choose";
  const s = document.createElement("summary");
  const summary = () => (s.textContent = filters[key].length === 0 ? `${name}: all` : `${name}: ${filters[key].join(", ")}`);
  summary();
  d.append(s);
  for (const v of all) {
    const label = el("label", "");
    const check = document.createElement("input");
    check.type = "checkbox";
    check.checked = filters[key].includes(v);
    check.addEventListener("change", () => {
      const chosen = filters[key];
      set({ [key]: check.checked ? [...chosen, v] : chosen.filter((c) => c !== v) });
      summary();
    });
    label.append(check, ` ${v}`);
    d.append(label);
  }
  return d;
}

function pick(name: string, all: string[], chosen: string, done: (v: string) => void): HTMLElement {
  const s = document.createElement("select");
  for (const v of ["", ...all]) {
    const o = document.createElement("option");
    o.value = v;
    o.textContent = v ? `${name}: ${v}` : `${name}: all`;
    o.selected = v === chosen;
    s.append(o);
  }
  s.addEventListener("change", () => done(s.value));
  return s;
}

function chart(canvas: HTMLElement, n: Network): void {
  canvas.textContent = "";
  const { nodes, edges } = filter(n, filters);
  if (nodes.length === 0) {
    canvas.append(text("p", "No item is shown: change the filters."));
    return;
  }
  const places = layout(nodes, edges);
  const found = search(nodes, query);
  const xy = (id: string) => {
    const p = places.get(id)!;
    return { x: p.column * (nodeWidth + columnGap), y: p.layer * (nodeHeight + layerGap) };
  };
  const svg = svgEl("svg", { class: "graph" });
  const g = svgEl("g", {});
  svg.append(arrowHead(), g);
  for (const e of edges) g.append(edge(e, xy(e.from), xy(e.to), query !== "" && !found.has(e.from) && !found.has(e.to)));
  const colors = new Map(n.types.map((t, i) => [t, palette[i % palette.length]]));
  for (const node of nodes) g.append(nodeOf(node, xy(node.id), colors.get(node.type) ?? "--vscode-descriptionForeground", query !== "" && !found.has(node.id)));
  canvas.append(svg);
  const apply = () => g.setAttribute("transform", `translate(${view.x} ${view.y}) scale(${view.scale})`);
  apply();
  // the first item found, brought into view
  if (query !== "" && found.size > 0) {
    const first = nodes.find((x) => found.has(x.id))!;
    const p = xy(first.id);
    view = { ...view, x: canvas.clientWidth / 2 - (p.x + nodeWidth / 2) * view.scale, y: 60 - p.y * view.scale };
    apply();
  }
  svg.addEventListener("wheel", (e: WheelEvent) => {
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
    const r = svg.getBoundingClientRect();
    const mx = e.clientX - r.left;
    const my = e.clientY - r.top;
    view = { scale: view.scale * factor, x: mx - (mx - view.x) * factor, y: my - (my - view.y) * factor };
    apply();
  });
  svg.addEventListener("pointerdown", (down: PointerEvent) => {
    if ((down.target as Element).closest(".node")) return;
    const start = { ...view };
    const move = (e: PointerEvent) => {
      view = { ...view, x: start.x + e.clientX - down.clientX, y: start.y + e.clientY - down.clientY };
      apply();
    };
    const up = () => {
      svg.removeEventListener("pointermove", move);
      svg.removeEventListener("pointerup", up);
    };
    svg.addEventListener("pointermove", move);
    svg.addEventListener("pointerup", up);
  });
}

function nodeOf(n: GraphNode, p: { x: number; y: number }, color: string, dim: boolean): SVGElement {
  const g = svgEl("g", { class: `node${n.id === selected ? " selected" : ""}${dim ? " dim" : ""}${n.repository ? " other" : ""}`, transform: `translate(${p.x} ${p.y})` });
  const title = svgEl("title", {});
  title.textContent = n.repository ? `${n.id} (in ${n.repository})` : `${n.id} (${n.type}, ${n.status})\n${n.title}`;
  g.append(title, svgEl("rect", { width: nodeWidth, height: nodeHeight, rx: 4, style: `stroke: var(${color})` }));
  const label = svgEl("text", { x: 8, y: 17 });
  label.textContent = n.id.length > 20 ? `${n.id.slice(0, 19)}…` : n.id;
  g.append(label);
  g.addEventListener("click", (e) => {
    e.stopPropagation();
    selected = n.id;
    document.querySelectorAll(".node.selected").forEach((x) => x.classList.remove("selected"));
    g.classList.add("selected");
    vscode.postMessage({ kind: "select", id: n.id });
  });
  g.addEventListener("dblclick", () => vscode.postMessage({ kind: "open", id: n.id }));
  g.addEventListener("contextmenu", (e: MouseEvent) => {
    e.preventDefault();
    menu(e.clientX, e.clientY, n);
  });
  return g;
}

function edge(e: GraphEdge, from: { x: number; y: number }, to: { x: number; y: number }, dim: boolean): SVGElement {
  // from the top of the item that links to the bottom of the one it links to
  const x1 = from.x + nodeWidth / 2;
  const y1 = from.y;
  const x2 = to.x + nodeWidth / 2;
  const y2 = to.y + nodeHeight;
  const mid = (y1 + y2) / 2;
  const state = e.state.replace(/ /g, "-");
  const path = svgEl("path", { d: `M ${x1} ${y1} C ${x1} ${mid}, ${x2} ${mid}, ${x2} ${y2}`, class: `edge ${state}${dim ? " dim" : ""}`, "marker-end": "url(#arrow)" });
  const title = svgEl("title", {});
  title.textContent = `${e.from} ${e.type} ${e.to}${e.state ? ` (${e.state})` : ""}`;
  path.append(title);
  return path;
}

function arrowHead(): SVGElement {
  const defs = svgEl("defs", {});
  const marker = svgEl("marker", { id: "arrow", viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: "auto-start-reverse" });
  marker.append(svgEl("path", { d: "M 0 0 L 10 5 L 0 10 z", class: "arrow" }));
  defs.append(marker);
  return defs;
}

const actions: [string, string][] = [
  ["open", "Open"],
  ["trace", "Trace"],
  ["copy", "Copy ID"],
  ["review", "Review its links"],
  ["approve", "Approve"],
];

function details(html: string): void {
  const box = document.querySelector(".details");
  if (!box) return;
  box.textContent = "";
  const buttons = el("div", "actions");
  for (const [kind, label] of actions) {
    const b = el("button", "");
    b.textContent = label;
    b.addEventListener("click", () => vscode.postMessage({ kind, id: selected }));
    buttons.append(b);
  }
  const body = el("div", "trace");
  // the HTML the server rendered; its links choose or open items
  body.innerHTML = html;
  body.addEventListener("click", (e) => {
    const a = (e.target as Element).closest("a");
    if (!a) return;
    e.preventDefault();
    const href = a.getAttribute("href") ?? "";
    if (href.startsWith("skein:item/")) {
      selected = decodeURIComponent(href.slice("skein:item/".length));
      draw();
    } else vscode.postMessage({ kind: "link", href });
  });
  box.append(buttons, body);
}

function menu(x: number, y: number, n: GraphNode): void {
  closeMenu();
  const m = el("div", "menu");
  m.style.left = `${x}px`;
  m.style.top = `${y}px`;
  for (const [kind, label] of actions) {
    if (n.repository && kind !== "copy") continue;
    const item = el("div", "menu-item");
    item.textContent = label;
    item.addEventListener("click", () => {
      closeMenu();
      vscode.postMessage({ kind, id: n.id });
    });
    m.append(item);
  }
  document.body.append(m);
}

function closeMenu(): void {
  document.querySelectorAll(".menu").forEach((m) => m.remove());
}

function el(tag: string, cls: string): HTMLElement {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  return e;
}

function text(tag: string, content: string): HTMLElement {
  const e = el(tag, "");
  e.textContent = content;
  return e;
}

function svgEl(tag: string, attrs: Record<string, string | number>): SVGElement {
  const e = document.createElementNS(svgNs, tag) as SVGElement;
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  return e;
}
