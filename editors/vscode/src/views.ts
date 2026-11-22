// The trace and coverage views: web views of the HTML the server renders
// (skein/trace, skein/coverage), one of each, shown again when asked for
// again. Their links open items and places in the editor. And the
// planning view (dist/plan.js), on skein/schedule and skein/plan.

import * as vscode from "vscode";
import { Server } from "./client";
import { nonce, page, parseLink, planPage } from "./page";

export class Views {
  private trace: vscode.WebviewPanel | undefined;
  private coverage: vscode.WebviewPanel | undefined;
  private plan: vscode.WebviewPanel | undefined;

  constructor(
    private readonly server: Server,
    private readonly open: (id: string) => Promise<void>,
    private readonly extensionUri: vscode.Uri,
  ) {}

  /** The planning view: a Gantt chart and a board whose drags are written into the items */
  async showPlan(): Promise<void> {
    if (this.plan) {
      this.plan.reveal(undefined, false);
      await this.sendPlan();
      return;
    }
    const dist = vscode.Uri.joinPath(this.extensionUri, "dist");
    const panel = vscode.window.createWebviewPanel("skein.plan", "skein Plan", vscode.ViewColumn.Active, {
      enableScripts: true,
      localResourceRoots: [dist],
      retainContextWhenHidden: true,
    });
    const script = panel.webview.asWebviewUri(vscode.Uri.joinPath(dist, "plan.js"));
    panel.webview.html = planPage(script.toString(), panel.webview.cspSource, nonce());
    panel.webview.onDidReceiveMessage((m: { kind: string; id?: string; start?: string; finish?: string; status?: string }) => this.planMessage(m));
    panel.onDidDispose(() => (this.plan = undefined));
    this.plan = panel;
  }

  private async sendPlan(): Promise<void> {
    const schedule = await this.server.request<object | null>("skein/schedule");
    await this.plan?.webview.postMessage({ kind: "data", schedule: schedule ?? { items: [], statuses: [], workdays: [], holidays: [] } });
  }

  private async planMessage(m: { kind: string; id?: string; start?: string; finish?: string; status?: string }): Promise<void> {
    if (m.kind === "ready") return this.sendPlan();
    if (m.kind === "open" && m.id) return this.open(m.id);
    if (m.kind === "plan" && m.id) {
      await this.server.request("skein/plan", { id: m.id, start: m.start, finish: m.finish, status: m.status });
      // what was written, or, when it was refused, what was there
      await this.sendPlan();
    }
  }

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

  /** Shows the coverage and the plan again, where their views are open */
  async refresh(): Promise<void> {
    if (this.coverage) await this.showCoverage();
    if (this.plan) await this.sendPlan();
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

  /** Opens what a link of a view leads to: an item, a place in a file, or a page of the web */
  async follow(href: string): Promise<void> {
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
