// The planning view's page: a Gantt chart whose bars are dragged to move
// an item or to change its length, and a board whose cards are dragged
// between statuses. Each drag is sent to the extension, which has the
// server write it into the item's file; the extension then sends the
// schedule again. Bundled on its own into dist/plan.js.

import { Bar, columns, daysMoved, fromDay, isWorking, layout, planChange, Schedule, weekday } from "../planmodel";

declare function acquireVsCodeApi(): { postMessage(message: unknown): void; getState(): unknown; setState(state: unknown): void };

const vscode = acquireVsCodeApi();
const dayWidth = 28;
const rowHeight = 26;
const headerHeight = 36;
const svgNs = "http://www.w3.org/2000/svg";

let schedule: Schedule | undefined;
let tab: "gantt" | "board" = ((vscode.getState() as { tab?: string } | undefined)?.tab as "gantt" | "board") ?? "gantt";

window.addEventListener("message", (event: MessageEvent) => {
  const m = event.data as { kind: string; schedule?: Schedule };
  if (m.kind === "data" && m.schedule) {
    schedule = m.schedule;
    draw();
  }
});
vscode.postMessage({ kind: "ready" });

function draw(): void {
  const root = document.getElementById("root")!;
  root.textContent = "";
  const tabs = el("div", "tabs");
  for (const [name, label] of [["gantt", "Gantt"], ["board", "Board"]] as const) {
    const b = el("button", name === tab ? "tab active" : "tab");
    b.textContent = label;
    b.addEventListener("click", () => {
      tab = name;
      vscode.setState({ tab });
      draw();
    });
    tabs.append(b);
  }
  root.append(tabs);
  if (!schedule || schedule.items.length === 0) {
    root.append(text("p", "No work items: no item type has [planning]."));
    return;
  }
  root.append(tab === "gantt" ? gantt(schedule) : board(schedule));
}

function gantt(s: Schedule): HTMLElement {
  const box = el("div", "gantt");
  const l = layout(s);
  const names = el("div", "names");
  names.style.paddingTop = `${headerHeight}px`;
  for (const bar of l.bars) {
    const n = el("div", "name");
    n.style.height = `${rowHeight}px`;
    n.textContent = bar.item.id;
    n.title = bar.item.title;
    n.addEventListener("click", () => vscode.postMessage({ kind: "open", id: bar.item.id }));
    names.append(n);
  }
  const days = l.last - l.first + 1;
  const width = days * dayWidth;
  const height = headerHeight + l.bars.length * rowHeight;
  const svg = svgEl("svg", { width, height, class: "timeline" });
  for (let d = l.first; d <= l.last; d++) {
    const x = (d - l.first) * dayWidth;
    if (!isWorking(s, d)) svg.append(svgEl("rect", { x, y: 0, width: dayWidth, height, class: "off" }));
    if (weekday(d) === 0) {
      svg.append(svgEl("line", { x1: x, y1: 0, x2: x, y2: height, class: "week" }));
      svg.append(svgText(fromDay(d), x + 3, 13, "week-label"));
    }
    svg.append(svgText(fromDay(d).slice(8), x + dayWidth / 2, 30, "day-label"));
  }
  const byId = new Map(l.bars.map((b) => [b.item.id, b]));
  for (const bar of l.bars) {
    for (const p of bar.item.after) {
      const from = byId.get(p);
      if (from) svg.append(arrow(l.first, from, bar));
    }
  }
  for (const bar of l.bars) svg.append(barOf(l.first, bar));
  const scroll = el("div", "scroll");
  scroll.append(svg);
  box.append(names, scroll);
  const wrap = el("div", "");
  wrap.append(box);
  if (l.unscheduled.length > 0) wrap.append(text("p", `Not scheduled: ${l.unscheduled.map((i) => i.id).join(", ")}`));
  wrap.append(text("p", "Drag a bar to move it, or its right end to change its length. A float item moved by hand becomes fixed.", "hint"));
  return wrap;
}

function barOf(first: number, bar: Bar): SVGElement {
  const x = (bar.first - first) * dayWidth;
  const y = headerHeight + bar.row * rowHeight + 5;
  const g = svgEl("g", { class: bar.item.critical ? "bar critical" : "bar" });
  const title = svgEl("title", {});
  title.textContent = `${bar.item.id}: ${fromDay(bar.first)} to ${fromDay(bar.last)}${bar.item.slack !== undefined ? `, slack ${bar.item.slack}` : ""}`;
  g.append(title);
  if (bar.item.milestone) {
    const cx = x + dayWidth / 2;
    const cy = y + 8;
    g.append(svgEl("path", { d: `M ${cx} ${cy - 8} L ${cx + 8} ${cy} L ${cx} ${cy + 8} L ${cx - 8} ${cy} Z`, class: "milestone" }));
    drag(g, bar, "move");
    return g;
  }
  const w = (bar.last - bar.first + 1) * dayWidth;
  const body = svgEl("rect", { x, y, width: w, height: 16, rx: 3, class: "body" });
  const end = svgEl("rect", { x: x + w - 6, y, width: 6, height: 16, class: "end" });
  g.append(body, end);
  drag(body, bar, "move");
  drag(end, bar, "end");
  return g;
}

/** A drag of `target` that moves the bar or its end; sent on release */
function drag(target: SVGElement, bar: Bar, edge: "move" | "end"): void {
  target.addEventListener("pointerdown", (down: PointerEvent) => {
    down.preventDefault();
    try {
      target.setPointerCapture(down.pointerId);
    } catch {
      // a pointer the page does not know: the drag works without capture
    }
    const group = target.closest("g")!;
    const move = (e: PointerEvent) => {
      const days = daysMoved(e.clientX - down.clientX, dayWidth);
      group.setAttribute("transform", edge === "move" ? `translate(${days * dayWidth} 0)` : "");
      if (edge === "end") {
        const body = group.querySelector(".body");
        const w = Math.max(1, bar.last - bar.first + 1 + days) * dayWidth;
        body?.setAttribute("width", String(w));
      }
    };
    const up = (e: PointerEvent) => {
      target.removeEventListener("pointermove", move);
      target.removeEventListener("pointerup", up);
      const change = planChange(bar, edge, daysMoved(e.clientX - down.clientX, dayWidth));
      if (change) vscode.postMessage({ kind: "plan", ...change });
      else draw();
    };
    target.addEventListener("pointermove", move);
    target.addEventListener("pointerup", up);
  });
}

function arrow(first: number, from: Bar, to: Bar): SVGElement {
  const x1 = (from.last - first + 1) * dayWidth;
  const y1 = headerHeight + from.row * rowHeight + 13;
  const x2 = (to.first - first) * dayWidth;
  const y2 = headerHeight + to.row * rowHeight + 13;
  const mid = Math.max(x1 + 6, x2 - 6);
  return svgEl("path", { d: `M ${x1} ${y1} H ${mid} V ${y2} H ${x2}`, class: "arrow" });
}

function board(s: Schedule): HTMLElement {
  const box = el("div", "board");
  for (const column of columns(s)) {
    const col = el("div", "column");
    col.append(text("h3", column.status));
    col.addEventListener("dragover", (e) => {
      e.preventDefault();
      col.classList.add("over");
    });
    col.addEventListener("dragleave", () => col.classList.remove("over"));
    col.addEventListener("drop", (e) => {
      e.preventDefault();
      col.classList.remove("over");
      const id = e.dataTransfer?.getData("text/plain");
      const item = s.items.find((i) => i.id === id);
      if (item && item.status !== column.status) vscode.postMessage({ kind: "plan", id, status: column.status });
    });
    for (const item of column.items) {
      const card = el("div", item.critical ? "card critical" : "card");
      card.draggable = true;
      card.append(text("div", item.id, "card-id"), text("div", item.title, "card-title"));
      const when = item.start && item.finish ? `${item.start} to ${item.finish}` : "not scheduled";
      card.append(text("div", [when, ...item.assignees].join(" · "), "card-meta"));
      card.addEventListener("dragstart", (e) => e.dataTransfer?.setData("text/plain", item.id));
      card.addEventListener("dblclick", () => vscode.postMessage({ kind: "open", id: item.id }));
      col.append(card);
    }
    box.append(col);
  }
  return box;
}

function el(tag: string, cls: string): HTMLElement {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  return e;
}

function text(tag: string, content: string, cls = ""): HTMLElement {
  const e = el(tag, cls);
  e.textContent = content;
  return e;
}

function svgEl(tag: string, attrs: Record<string, string | number>): SVGElement {
  const e = document.createElementNS(svgNs, tag) as SVGElement;
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  return e;
}

function svgText(content: string, x: number, y: number, cls: string): SVGElement {
  const t = svgEl("text", { x, y, class: cls });
  t.textContent = content;
  return t;
}
