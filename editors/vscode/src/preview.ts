// skein in VS Code's Markdown preview (package.json:
// markdown.markdownItPlugins, markdown.previewStyles): the plugin of
// previewplugin.ts, fed with what the server renders. A document is
// rendered as it is saved, since the server reads the project from the
// files; while it has changes not saved, the preview shows it as written.

import * as vscode from "vscode";
import { Server } from "./client";
import { MarkdownIt, normalize, plugin, PreviewCache } from "./previewplugin";

export class Preview {
  private readonly cache = new PreviewCache();
  /** the documents being asked for, so that each is asked once at a time */
  private readonly asking = new Set<string>();

  constructor(private readonly server: Server) {}

  /** What the extension gives the Markdown extension */
  extendMarkdownIt<T extends MarkdownIt>(md: T): T {
    return plugin(this.cache, (source, env) => void this.ask(source, env))(md);
  }

  /** Renders everything again, after a change to the project */
  refresh(): void {
    this.cache.clear();
    void vscode.commands.executeCommand("markdown.preview.refresh");
  }

  private async ask(source: string, env: unknown): Promise<void> {
    const document = documentOf(source, env);
    if (!document || document.isDirty || document.uri.scheme !== "file") return;
    const key = document.uri.toString();
    if (this.asking.has(key)) return;
    this.asking.add(key);
    try {
      const result = await this.server.request<{ source: string; rendered: string } | null>("skein/render", { uri: key });
      // the file on disk is what the preview shows: rendered, it is shown so
      if (!result || normalize(result.source) !== normalize(source)) return;
      this.cache.put(result.source, result.rendered);
      await vscode.commands.executeCommand("markdown.preview.refresh");
    } finally {
      this.asking.delete(key);
    }
  }
}

/** The document the preview renders: the one it names, else the open one with this text */
function documentOf(source: string, env: unknown): vscode.TextDocument | undefined {
  const current = (env as { currentDocument?: vscode.Uri } | undefined)?.currentDocument;
  if (current) {
    const doc = vscode.workspace.textDocuments.find((d) => d.uri.toString() === current.toString());
    if (doc) return doc;
  }
  const text = normalize(source);
  return vscode.workspace.textDocuments.find((d) => d.languageId === "markdown" && normalize(d.getText()) === text);
}
