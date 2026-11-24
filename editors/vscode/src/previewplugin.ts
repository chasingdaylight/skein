// The markdown-it plugin of VS Code's Markdown preview: a document skein
// has rendered (skein/render, as `skein render` writes it) is shown as
// rendered: markers as anchors and IDs, references as links, unresolved
// references marked. The rendering is the server's, kept by the text it was
// rendered from; a text not yet rendered is shown as it is, and asked for.
// No VS Code here, so that it is tested with Node alone.

/** The renderings, by the text they were rendered from */
export class PreviewCache {
  private readonly rendered = new Map<string, string>();
  /** the most kept, so that old texts do not pile up */
  private readonly limit: number;

  constructor(limit = 64) {
    this.limit = limit;
  }

  put(source: string, rendered: string): void {
    if (this.rendered.size >= this.limit) this.rendered.clear();
    this.rendered.set(normalize(source), rendered);
  }

  get(source: string): string | undefined {
    return this.rendered.get(normalize(source));
  }

  clear(): void {
    this.rendered.clear();
  }
}

/** The same text whatever its line ends */
export function normalize(text: string): string {
  return text.replace(/\r\n/g, "\n");
}

/** What the plugin needs of markdown-it */
export interface MarkdownIt {
  core: { ruler: { before(before: string, name: string, rule: (state: { src: string; env: unknown }) => void): void } };
}

/** The plugin: the rendering in place of the source when there is one; `missing` told of a source without */
export function plugin(cache: PreviewCache, missing: (source: string, env: unknown) => void): <T extends MarkdownIt>(md: T) => T {
  return (md) => {
    md.core.ruler.before("normalize", "skein", (state) => {
      const rendered = cache.get(state.src);
      if (rendered !== undefined) state.src = rendered;
      else missing(state.src, state.env);
    });
    return md;
  };
}
