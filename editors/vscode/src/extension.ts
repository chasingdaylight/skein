// skein for VS Code: a client of `skein lsp`, which the package carries
// (bin/), with the views the server feeds: the items in a tree, an item's
// trace, the coverage page, and the coverage in the status bar. It also
// puts the program on the PATH of VS Code's terminals. The highlighting
// needs none of this; it is the grammar's.

import * as path from "node:path";
import * as vscode from "vscode";
import { Server } from "./client";
import * as commands from "./commands";
import { findProgram } from "./program";
import { Status } from "./status";
import { ItemTree } from "./tree";
import { Views } from "./views";

/** How long after a change to the files the views are read again */
const settle_ms = 500;

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  updateTerminals(context);
  const output = vscode.window.createOutputChannel("skein Language Server", { log: true });
  const server = new Server(context, output);
  const tree = new ItemTree(server);
  const views = new Views(server, (id) => commands.openItem(tree, id), context.extensionUri);
  const status = new Status(server);
  context.subscriptions.push(output, status, vscode.window.registerTreeDataProvider("skein.items", tree));

  let timer: NodeJS.Timeout | undefined;
  const refresh = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = undefined;
      void tree.refresh();
      void status.refresh();
      void views.refresh();
    }, settle_ms);
  };
  commands.register(context, server, tree, views, refresh);

  const watcher = vscode.workspace.createFileSystemWatcher("**/*.{md,toml,yaml,yml,json}");
  context.subscriptions.push(
    watcher,
    watcher.onDidCreate(refresh),
    watcher.onDidDelete(refresh),
    watcher.onDidChange(refresh),
    vscode.workspace.onDidSaveTextDocument(refresh),
    server.onDidChange(refresh),
    vscode.workspace.onDidGrantWorkspaceTrust(() => void server.restart()),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("skein.path")) {
        updateTerminals(context);
        output.info("skein.path changed: restarting the language server");
        void server.restart();
      }
      if (event.affectsConfiguration("skein.statusBar.coverage")) void status.refresh();
    }),
  );
  running = server;

  const project = await hasProject();
  await vscode.commands.executeCommand("setContext", "skein.project", project);
  if (project) await server.restart();
}

let running: Server | undefined;

export async function deactivate(): Promise<void> {
  await running?.stop();
}

/** Whether the workspace's first folder is a skein project */
async function hasProject(): Promise<boolean> {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) return false;
  try {
    await vscode.workspace.fs.stat(vscode.Uri.joinPath(folder.uri, ".skein", "config.toml"));
    return true;
  } catch {
    return false;
  }
}

/** Puts the directory of the program first on the PATH of the terminals opened from now on */
function updateTerminals(context: vscode.ExtensionContext): void {
  const env = context.environmentVariableCollection;
  env.clear();
  const program = findProgram(vscode.workspace.getConfiguration("skein").get<string>("path", ""), context.extensionPath);
  if (!program) return;
  env.description = "Adds skein to the PATH";
  env.prepend("PATH", path.dirname(program) + path.delimiter);
}
