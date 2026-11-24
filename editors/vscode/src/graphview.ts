// The graph view (dist/graph.js): the network of items from skein/graph;
// a chosen item's trace beside it (skein/trace), and the actions on an
// item: open, trace, copy its ID, review its links, approve it.

import * as vscode from "vscode";
import { Server } from "./client";
import { graphPage, nonce } from "./page";
import { run } from "./run";
import { Views } from "./views";

type Message = { kind: string; id?: string; href?: string };

export class GraphView {
  private panel: vscode.WebviewPanel | undefined;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly server: Server,
    private readonly views: Views,
    private readonly open: (id: string) => Promise<void>,
  ) {}

  show(): void {
    if (this.panel) {
      this.panel.reveal(undefined, false);
      return;
    }
    const dist = vscode.Uri.joinPath(this.context.extensionUri, "dist");
    const panel = vscode.window.createWebviewPanel("skein.graph", "Skein Graph", vscode.ViewColumn.Active, {
      enableScripts: true,
      localResourceRoots: [dist],
      retainContextWhenHidden: true,
    });
    const script = panel.webview.asWebviewUri(vscode.Uri.joinPath(dist, "graph.js"));
    panel.webview.html = graphPage(script.toString(), panel.webview.cspSource, nonce());
    panel.webview.onDidReceiveMessage((m: Message) => this.message(m));
    panel.onDidDispose(() => (this.panel = undefined));
    this.panel = panel;
  }

  /** Draws the network again, after a change to the project */
  async refresh(): Promise<void> {
    if (!this.panel) return;
    const network = await this.server.request<object | null>("skein/graph");
    if (network) await this.panel.webview.postMessage({ kind: "data", network });
  }

  private async message(m: Message): Promise<void> {
    const id = m.id;
    switch (m.kind) {
      case "ready":
        return this.refresh();
      case "select": {
        if (!id) return;
        const trace = await this.server.request<{ html: string }>("skein/trace", { id });
        await this.panel?.webview.postMessage({ kind: "details", id, html: trace?.html ?? "" });
        return;
      }
      case "link":
        if (m.href) await this.views.follow(m.href);
        return;
    }
    if (!id) return;
    switch (m.kind) {
      case "open":
        return this.open(id);
      case "trace":
        return this.views.showTrace(id);
      case "copy":
        await vscode.env.clipboard.writeText(id);
        return;
      case "review":
      case "approve":
        try {
          const said = await run(this.context, [m.kind, id]);
          void vscode.window.showInformationMessage(said.trim());
        } catch (err) {
          void vscode.window.showErrorMessage(err instanceof Error ? err.message : String(err));
        }
        await this.refresh();
        return;
    }
  }
}
