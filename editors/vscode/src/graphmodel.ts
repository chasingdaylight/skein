// The graph view's model: the network as the server gives it
// (skein/graph), the filters, and where each node goes. Nodes are laid out
// in layers, each item above the items that link to it (a requirement
// above the tests that verify it), and in each layer by where what they
// link to is. No VS Code and no page here, so that it is tested with Node
// alone; the page's script (webview/graph.ts) draws it.

export interface GraphNode {
  id: string;
  type: string;
  status: string;
  title: string;
  uri: string;
  line: number;
  source: string;
  profiles: string[];
  /** the repository of an item of another one; empty for this one's */
  repository: string;
}

export interface GraphEdge {
  from: string;
  to: string;
  type: string;
  /** "reviewed", "suspect", "never reviewed", or "" */
  state: string;
}

export interface Network {
  nodes: GraphNode[];
  edges: GraphEdge[];
  types: string[];
  links: string[];
  profiles: string[];
  sources: string[];
}

export interface Filters {
  /** the item types shown; all when empty */
  types: string[];
  /** the link types shown; all when empty */
  links: string[];
  /** only the items of this profile; all when empty */
  profile: string;
  /** only the items of this source; all when empty */
  source: string;
  /** the items of other repositories too */
  others: boolean;
}

export const noFilters: Filters = { types: [], links: [], profile: "", source: "", others: true };

/** The nodes and edges that pass the filters; an edge only between nodes shown */
export function filter(net: Network, f: Filters): { nodes: GraphNode[]; edges: GraphEdge[] } {
  const nodes = net.nodes.filter((n) => {
    if (n.repository) return f.others;
    if (f.types.length > 0 && !f.types.includes(n.type)) return false;
    if (f.profile && !n.profiles.includes(f.profile)) return false;
    if (f.source && n.source !== f.source) return false;
    return true;
  });
  const shown = new Set(nodes.map((n) => n.id));
  const edges = net.edges.filter((e) => shown.has(e.from) && shown.has(e.to) && (f.links.length === 0 || f.links.includes(e.type)));
  return { nodes, edges };
}

/** The nodes whose ID or title has every word of `query`, in any case */
export function search(nodes: GraphNode[], query: string): Set<string> {
  const words = query.toLowerCase().split(/\s+/).filter((w) => w);
  if (words.length === 0) return new Set();
  return new Set(nodes.filter((n) => words.every((w) => n.id.toLowerCase().includes(w) || n.title.toLowerCase().includes(w))).map((n) => n.id));
}

export interface Place {
  layer: number;
  column: number;
}

/** Each node's layer (0 at the top: what nothing shown links on from) and column */
export function layout(nodes: GraphNode[], edges: GraphEdge[]): Map<string, Place> {
  const targets = new Map<string, string[]>();
  for (const n of nodes) targets.set(n.id, []);
  for (const e of edges) targets.get(e.from)?.push(e.to);
  // a node's layer: one below the lowest of what it links to
  const layer = new Map<string, number>();
  const visiting = new Set<string>();
  const layerOf = (id: string): number => {
    const known = layer.get(id);
    if (known !== undefined) return known;
    // a loop of links: its nodes in one layer
    if (visiting.has(id)) return 0;
    visiting.add(id);
    let l = 0;
    for (const t of targets.get(id) ?? []) l = Math.max(l, layerOf(t) + 1);
    visiting.delete(id);
    layer.set(id, l);
    return l;
  };
  for (const n of nodes) layerOf(n.id);

  const layers: string[][] = [];
  for (const n of nodes) (layers[layer.get(n.id)!] ??= []).push(n.id);
  const places = new Map<string, Place>();
  for (const [l, ids] of layers.entries()) {
    if (!ids) continue;
    // under what they link to, on average; then by ID
    const weight = (id: string) => {
      const above = (targets.get(id) ?? []).map((t) => places.get(t)?.column).filter((c): c is number => c !== undefined);
      return above.length === 0 ? Number.POSITIVE_INFINITY : above.reduce((a, b) => a + b, 0) / above.length;
    };
    const ordered = [...ids].sort((a, b) => weight(a) - weight(b) || (a < b ? -1 : a > b ? 1 : 0));
    ordered.forEach((id, column) => places.set(id, { layer: l, column }));
  }
  return places;
}
