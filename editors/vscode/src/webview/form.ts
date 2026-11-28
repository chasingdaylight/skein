// The item form's page: an item's type, ID, category, status, attributes
// and links, as fields its type allows; for a new item, where it goes and
// its text. Saving sends the form to the extension, which has the server
// write it. Bundled on its own into dist/form.js.

import { Form, initial, problems, toSave, Values } from "../formmodel";

declare function acquireVsCodeApi(): { postMessage(message: unknown): void };

const vscode = acquireVsCodeApi();
let form: Form | undefined;
let values: Values | undefined;

window.addEventListener("message", (event: MessageEvent) => {
  const m = event.data as { kind: string; form?: Form; message?: string };
  if (m.kind === "form" && m.form) {
    form = m.form;
    values = initial(form);
    draw();
  }
  if (m.kind === "error") say(m.message ?? "", true);
});
vscode.postMessage({ kind: "ready" });

function draw(): void {
  const root = document.getElementById("root")!;
  root.textContent = "";
  if (!form || !values) return;
  const f = form;
  const v = values;
  root.append(text("h1", f.item ? `Edit ${f.item.id}` : "New item"));
  if (f.type.description) root.append(text("p", f.type.description, "hint"));
  const grid = el("div", "fields");
  if (!f.item) {
    grid.append(field("Type", select(f.types, f.type.name, false, (t) => vscode.postMessage({ kind: "type", type: t }))));
    grid.append(field("ID", input(v.id, f.type.numbered ? "the next free number" : "the item's ID", (x) => (v.id = x))));
    if (!f.itemFiles) grid.append(field("Document", select(f.documents, v.document, false, (x) => (v.document = x))));
  }
  if (f.type.categories.length > 0) grid.append(field("Category", select(f.type.categories, v.category, true, (x) => (v.category = x))));
  grid.append(field("Status", select(f.type.statuses, v.status, true, (x) => (v.status = x), `${f.type.statuses[0]} (the first)`)));
  if (f.type.verification.length > 0) grid.append(field("Verification", select(f.type.verification, v.verification, true, (x) => (v.verification = x))));
  for (const a of f.type.attributes) {
    const set = (x: string) => (v.attributes[a.name] = x);
    const cur = v.attributes[a.name] ?? "";
    let control: HTMLElement;
    if (a.values.length > 0 && !a.list) control = select(a.values, cur, true, set);
    else if (a.kind === "boolean") control = select(["true", "false"], cur, true, set);
    else control = input(cur, a.list ? "values, separated by commas" : "", set, a.kind === "integer" ? "number" : a.kind === "date" ? "date" : "text");
    grid.append(field(a.required ? `${a.name} *` : a.name, control));
  }
  for (const l of f.type.links) {
    const listId = `targets-${l.name}`;
    const list = el("datalist", "");
    list.id = listId;
    for (const t of l.targets) {
      const o = document.createElement("option");
      o.value = t;
      list.append(o);
    }
    const box = input(v.links[l.name] ?? "", "IDs, separated by commas", (x) => (v.links[l.name] = x));
    box.setAttribute("list", listId);
    const wrap = el("div", "");
    wrap.append(box, list);
    grid.append(field(`${l.name} →`, wrap));
  }
  if (!f.item) {
    const area = document.createElement("textarea");
    area.rows = 4;
    area.value = v.text;
    area.addEventListener("input", () => (v.text = area.value));
    grid.append(field("Text", area));
  }
  root.append(grid);
  const buttons = el("div", "buttons");
  const save = text("button", f.item ? "Save" : "Create");
  save.addEventListener("click", () => {
    const wrong = problems(f, v);
    if (wrong.length > 0) return say(wrong.join("; "), true);
    say("Saving…", false);
    vscode.postMessage({ kind: "save", save: toSave(f, v) });
  });
  const cancel = text("button", "Cancel", "secondary");
  cancel.addEventListener("click", () => vscode.postMessage({ kind: "cancel" }));
  buttons.append(save, cancel);
  root.append(buttons, el("p", "said"));
}

function say(message: string, error: boolean): void {
  const p = document.querySelector(".said");
  if (!p) return;
  p.textContent = message;
  p.className = error ? "said error" : "said";
}

function field(label: string, control: HTMLElement): HTMLElement {
  const row = el("label", "field");
  row.append(text("span", label, "label"), control);
  return row;
}

function select(options: string[], chosen: string, empty: boolean, done: (v: string) => void, emptyLabel = "(none)"): HTMLElement {
  const s = document.createElement("select");
  for (const o of empty ? ["", ...options] : options) {
    const opt = document.createElement("option");
    opt.value = o;
    opt.textContent = o || emptyLabel;
    opt.selected = o === chosen;
    s.append(opt);
  }
  s.addEventListener("change", () => done(s.value));
  return s;
}

function input(value: string, placeholder: string, done: (v: string) => void, type = "text"): HTMLInputElement {
  const i = document.createElement("input");
  i.type = type;
  i.value = value;
  i.placeholder = placeholder;
  i.addEventListener("input", () => done(i.value));
  return i;
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
