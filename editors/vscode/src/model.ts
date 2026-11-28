// The items of a project as the server gives them (skein/items), and the
// tree the side bar shows of them: by source, when there are several, then
// by file, with each item's parts under it. No VS Code here, so that it is
// tested with Node alone.

/** One item, as `skein/items` gives it */
export interface ItemInfo {
  id: string;
  type: string;
  category?: string;
  status: string;
  uri: string;
  /** from the project's root, with forward slashes */
  file: string;
  /** 0-based */
  line: number;
  parent?: string;
  title: string;
  /** the source the file is in, or "" */
  source: string;
  removed: boolean;
}

export interface Items {
  project: string;
  sources: string[];
  items: ItemInfo[];
}

export type Node =
  | { kind: "source"; path: string; children: Node[] }
  | { kind: "file"; file: string; label: string; uri: string; children: Node[] }
  | { kind: "item"; item: ItemInfo; children: Node[] };

/** The nodes at the top of the tree */
export function buildTree(items: Items): Node[] {
  const bySource = new Map<string, Map<string, Node & { kind: "file" }>>();
  for (const s of items.sources) bySource.set(s, new Map());
  const nodes = new Map<string, Node & { kind: "item" }>();
  for (const item of items.items) nodes.set(item.id, { kind: "item", item, children: [] });

  for (const item of items.items) {
    const node = nodes.get(item.id)!;
    const whole = item.parent !== undefined ? nodes.get(item.parent) : undefined;
    // a part goes under its whole, when that is in the same file
    if (whole && whole.item.file === item.file) {
      whole.children.push(node);
      continue;
    }
    let files = bySource.get(item.source);
    if (!files) {
      files = new Map();
      bySource.set(item.source, files);
    }
    let file = files.get(item.file);
    if (!file) {
      file = { kind: "file", file: item.file, label: relative(item.source, item.file), uri: item.uri, children: [] };
      files.set(item.file, file);
    }
    file.children.push(node);
  }

  const sources: Node[] = [];
  for (const [path, files] of bySource) {
    if (files.size === 0) continue;
    const children = [...files.values()].sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : 0));
    sources.push({ kind: "source", path: path === "" ? "(no source)" : path, children });
  }
  // one source: its files are the top of the tree
  return sources.length === 1 ? sources[0].children : sources;
}

/** `file` from the directory `source` */
function relative(source: string, file: string): string {
  return source !== "" && file.startsWith(source + "/") ? file.slice(source.length + 1) : file;
}

/** What the tree shows beside an item's ID */
export function describe(item: ItemInfo): string {
  const kind = item.category ? `${item.type}, ${item.category}` : item.type;
  return `${kind}, ${item.status}`;
}

/** The share of what is expected that is covered, for the status bar; with the project's name where there are several */
export function coverageText(covered: number, total: number, project?: string): { text: string; tooltip: string } {
  const name = project ? ` ${project}` : "";
  if (total === 0) return { text: `$(checklist)${name || " Skein"}`, tooltip: "skein: nothing is expected" };
  const percent = Math.floor((covered * 100) / total);
  return { text: `$(checklist)${name} ${percent}%`, tooltip: `skein: ${covered} of ${total} expected links and citations are there` };
}
