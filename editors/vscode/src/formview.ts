// The item form (dist/form.js): New Item and Edit Item. The form comes
// from skein/form, and is written by skein/saveItem; the item is then
// opened at its marker.

import * as vscode from "vscode";
import { Server } from "./client";
import { formPage, nonce } from "./page";

type Message = { kind: string; type?: string; save?: Record<string, unknown> };

export class FormView {
  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly server: Server,
    private readonly saved: () => void,
  ) {}

  /** A form for the item `id`, or for a new item of `type` (the first type when none) */
  async show(id?: string, type?: string): Promise<void> {
    const first = await this.server.request<object | null>("skein/form", id ? { id } : type ? { type } : {});
    if (!first) return;
    const dist = vscode.Uri.joinPath(this.context.extensionUri, "dist");
    const panel = vscode.window.createWebviewPanel("skein.form", id ? `Edit ${id}` : "New Skein item", vscode.ViewColumn.Beside, {
      enableScripts: true,
      localResourceRoots: [dist],
    });
    const script = panel.webview.asWebviewUri(vscode.Uri.joinPath(dist, "form.js"));
    panel.webview.html = formPage(script.toString(), panel.webview.cspSource, nonce());
    let form = first;
    panel.webview.onDidReceiveMessage(async (m: Message) => {
      switch (m.kind) {
        case "ready":
          await panel.webview.postMessage({ kind: "form", form });
          return;
        case "type": {
          const next = await this.server.request<object | null>("skein/form", { type: m.type });
          if (next) {
            form = next;
            await panel.webview.postMessage({ kind: "form", form });
          }
          return;
        }
        case "cancel":
          panel.dispose();
          return;
        case "save": {
          const done = await this.save(m.save ?? {});
          if (typeof done === "string") {
            await panel.webview.postMessage({ kind: "error", message: done });
            return;
          }
          panel.dispose();
          this.saved();
          const at = new vscode.Position(done.line, 0);
          await vscode.window.showTextDocument(vscode.Uri.parse(done.uri), { selection: new vscode.Range(at, at), viewColumn: vscode.ViewColumn.One });
          return;
        }
      }
    });
  }

  /** Writes the form; where the item is, or why it was not written */
  private async save(save: Record<string, unknown>): Promise<{ uri: string; line: number } | string> {
    const c = this.server.running;
    if (!c) return "skein: the language server is not running";
    try {
      return await c.sendRequest<{ uri: string; line: number }>("skein/saveItem", save);
    } catch (err) {
      return err && typeof err === "object" && "message" in err ? String((err as { message: unknown }).message) : String(err);
    }
  }
}
