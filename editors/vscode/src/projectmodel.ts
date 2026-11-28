// The projects the server serves (skein/projects), and which of them a
// file is in. No VS Code here, so that it is tested with Node alone.

/** One project, as `skein/projects` gives it */
export interface ProjectInfo {
  name: string;
  /** the URI of its root */
  uri: string;
}

/** The project whose root is nearest above the file `uri`, if any */
export function projectOf(projects: ProjectInfo[], uri: string, caseless: boolean): ProjectInfo | undefined {
  const norm = (u: string) => {
    const d = decodeURIComponent(u).replace(/\/+$/, "");
    return caseless ? d.toLowerCase() : d;
  };
  const file = norm(uri);
  let best: ProjectInfo | undefined;
  for (const p of projects) {
    const root = norm(p.uri);
    if (file !== root && !file.startsWith(root + "/")) continue;
    if (!best || root.length > norm(best.uri).length) best = p;
  }
  return best;
}

/** How a project is named where several are open: its name, and its folder when two share one */
export function labelOf(projects: ProjectInfo[], p: ProjectInfo): string {
  const same = projects.filter((q) => q.name === p.name).length;
  if (same < 2) return p.name;
  const folder = decodeURIComponent(p.uri).replace(/\/+$/, "").split("/").pop() ?? p.uri;
  return `${p.name} (${folder})`;
}
