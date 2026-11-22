// The commands of the extension (package.json, contributes.commands).

import { execFile } from "node:child_process";
import * as vscode from "vscode";
import { Server } from "./client";
import { findProgram } from "./program";
import { ItemTree } from "./tree";
import { Views } from "./views";

export function register(context: vscode.ExtensionContext, server: Server, tree: ItemTree, views: Views, refresh: () => void): void {
  const command = (name: string, run: (...args: never[]) => unknown) => context.subscriptions.push(vscode.commands.registerCommand(name, run));

  command("skein.showVersion", () => showVersion(context));
  command("skein.restartServer", () => server.restart());
  command("skein.refreshItems", () => refresh());
  command("skein.showCoverage", () => views.showCoverage());
  command("skein.openItem", async (id?: string) => {
    const chosen = id ?? (await pickItem(tree, "Go to an item"));
    if (chosen) await openItem(tree, chosen);
  });
  // from a lens or the tree: its item; from the editor: the item under
  // the cursor; else one chosen
  command("skein.trace", async (arg?: string | { item?: { id: string } }) => {
    const id = typeof arg === "string" ? arg : (arg?.item?.id ?? (await itemAtCursor(server)) ?? (await pickItem(tree, "Trace an item")));
    if (id) await views.showTrace(id);
  });
  command("skein.copyId", async (node?: { item?: { id: string } }) => {
    if (node?.item) await vscode.env.clipboard.writeText(node.item.id);
  });
  command("skein.pickLinked", async (_id: string, linked: { id: string; label: string }[]) => {
    const chosen = await vscode.window.showQuickPick(
      linked.map((l) => ({ label: l.label, id: l.id })),
      { placeHolder: "Go to a linked item" },
    );
    if (chosen) await openItem(tree, chosen.id);
  });
}

/** Opens the item `id` at its marker, or its file */
export async function openItem(tree: ItemTree, id: string): Promise<void> {
  if (!tree.item(id)) await tree.refresh();
  const item = tree.item(id);
  if (!item) {
    void vscode.window.showWarningMessage(`skein: there is no item '${id}'`);
    return;
  }
  const at = new vscode.Position(item.line, 0);
  await vscode.window.showTextDocument(vscode.Uri.parse(item.uri), { selection: new vscode.Range(at, at), viewColumn: vscode.ViewColumn.One });
}

async function itemAtCursor(server: Server): Promise<string | undefined> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return undefined;
  const found = await server.request<{ id: string } | null>("skein/itemAt", {
    textDocument: { uri: editor.document.uri.toString() },
    position: editor.selection.active,
  });
  return found?.id;
}

async function pickItem(tree: ItemTree, placeHolder: string): Promise<string | undefined> {
  if (tree.all().length === 0) await tree.refresh();
  const chosen = await vscode.window.showQuickPick(
    tree.all().map((i) => ({ label: i.id, description: i.type, detail: i.title })),
    { placeHolder, matchOnDetail: true },
  );
  return chosen?.label;
}

function showVersion(context: vscode.ExtensionContext): void {
  const configured = vscode.workspace.getConfiguration("skein").get<string>("path", "");
  const program = findProgram(configured, context.extensionPath);
  if (!program) {
    void vscode.window.showWarningMessage(
      configured.trim()
        ? `skein: there is no file '${configured}' (the setting skein.path).`
        : "skein: this package of the extension carries no skein program for this platform. Install skein and set skein.path, or put it on the PATH.",
    );
    return;
  }
  execFile(program, ["version"], { timeout: 10000 }, (error, stdout) => {
    if (error) {
      void vscode.window.showErrorMessage(`skein: could not run '${program}': ${error.message}`);
      return;
    }
    void vscode.window.showInformationMessage(`skein ${stdout.trim()} (${program})`);
  });
}
