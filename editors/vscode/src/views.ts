// The trace and coverage views: web views of the HTML the server renders
// (skein/trace, skein/coverage), one of each, shown again when asked for
// again. Their links open items and places in the editor.

import * as vscode from "vscode";
import { Server } from "./client";
import { nonce, page, parseLink } from "./page";

export class Views {
  private trace: vscode.WebviewPanel | undefined;
  private coverage: vscode.WebviewPanel | undefined;

  constructor(
    private readonly server: Server,
    private readonly open: (id: string) => Promise<void>,
  ) {}

  async showTrace(id: string): Promise<void> {
    const result = await this.server.request<{ id: string; html: string }>("skein/trace", { id });
    if (!result) return;
    this.trace = this.show(this.trace, "skein.trace", `Trace: ${result.id}`, result.html, () => (this.trace = undefined));
  }

  async showCoverage(): Promise<void> {
    const result = await this.server.request<{ html: string }>("skein/coverage");
    if (!result) return;
    this.coverage = this.show(this.coverage, "skein.coverage", "skein Coverage", result.html, () => (this.coverage = undefined));
  }

  /** Shows the coverage again, if its view is open */
  async refresh(): Promise<void> {
    if (this.coverage) await this.showCoverage();
  }

  private show(panel: vscode.WebviewPanel | undefined, type: string, title: string, html: string, closed: () => void): vscode.WebviewPanel {
    if (!panel) {
      panel = vscode.window.createWebviewPanel(type, title, { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true }, { enableScripts: true, localResourceRoots: [] });
      panel.webview.onDidReceiveMessage((m: { href?: string }) => this.follow(m.href ?? ""));
      panel.onDidDispose(closed);
    } else panel.reveal(undefined, true);
    panel.title = title;
    const n = nonce();
    panel.webview.html = page(title, html, n);
    return panel;
  }

  private async follow(href: string): Promise<void> {
    const link = parseLink(href);
    if (!link) return;
    switch (link.kind) {
      case "item":
        return this.open(link.id);
      case "file": {
        const folder = vscode.workspace.workspaceFolders?.[0];
        if (!folder) return;
        const uri = vscode.Uri.joinPath(folder.uri, ...link.file.split("/"));
        const at = new vscode.Position(link.line - 1, 0);
        await vscode.window.showTextDocument(uri, { selection: new vscode.Range(at, at), viewColumn: vscode.ViewColumn.One });
        return;
      }
      case "external":
        await vscode.env.openExternal(vscode.Uri.parse(link.href));
        return;
    }
  }
}
