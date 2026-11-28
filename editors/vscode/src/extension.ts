// skein for VS Code: a client of `skein lsp`, which the package carries
// (bin/), with the views the server feeds: the items in a tree, an item's
// trace, the coverage page, and the coverage in the status bar. It also
// puts the program on the PATH of VS Code's terminals, and gives VS Code's
// AI agents skein's tools (agents.ts), and renders skein's markers and
// references in the Markdown preview (preview.ts). The highlighting needs
// none of this; it is the grammar's.

import * as path from "node:path";
import * as vscode from "vscode";
import * as agents from "./agents";
import { Server } from "./client";
import * as commands from "./commands";
import { FormView } from "./formview";
import { GraphView } from "./graphview";
import { Preview } from "./preview";
import { Projects } from "./projects";
import { MarkdownIt } from "./previewplugin";
import { initProject } from "./init";
import { typeOfDocument } from "./formmodel";
import { findProgram } from "./program";
import { setRoot } from "./run";
import { Status } from "./status";
import { ItemTree } from "./tree";
import { Views } from "./views";

/** How long after a change to the files the views are read again */
const settle_ms = 500;

/** What the extension gives other extensions: the Markdown preview's plugin */
export interface Api {
  extendMarkdownIt<T extends MarkdownIt>(md: T): T;
}

export async function activate(context: vscode.ExtensionContext): Promise<Api> {
  updateTerminals(context);
  const output = vscode.window.createOutputChannel("Skein Language Server", { log: true });
  const server = new Server(context, output);
  const projects = new Projects(server);
  setRoot(() => projects.root());
  const tree = new ItemTree(server);
  const views = new Views(server, (id) => commands.openItem(tree, id), context.extensionUri, () => projects.root());
  const status = new Status(server);
  const preview = new Preview(server);
  const graph = new GraphView(context, server, views, (id) => commands.openItem(tree, id));
  const treeView = vscode.window.createTreeView("skein.items", { treeDataProvider: tree });
  context.subscriptions.push(output, status, projects, treeView);

  let timer: NodeJS.Timeout | undefined;
  const refresh = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = undefined;
      void tree.refresh();
      void status.refresh();
      void views.refresh();
      preview.refresh();
      void graph.refresh();
    }, settle_ms);
  };
  commands.register(context, server, tree, views, refresh);
  context.subscriptions.push(
    vscode.commands.registerCommand("skein.chooseProject", () => projects.choose()),
    vscode.window.onDidChangeActiveTextEditor(() => projects.follow()),
    // another project: the views show it
    projects.onDidChange(() => {
      treeView.description = projects.label;
      status.project = projects.label;
      views.closeTrace();
      refresh();
    }),
  );
  context.subscriptions.push(vscode.commands.registerCommand("skein.showGraph", () => graph.show()));
  const forms = new FormView(context, server, refresh);
  context.subscriptions.push(
    vscode.commands.registerCommand("skein.newItem", () => forms.show()),
    // from the editor: the new item goes into its document
    vscode.commands.registerCommand("skein.newItemHere", () => {
      const here = fileOfEditor(projects.root());
      return forms.show(undefined, typeOfDocument(tree.all(), here), here);
    }),
    vscode.commands.registerCommand("skein.initProject", async () => {
      if (!(await initProject(context))) return;
      await vscode.commands.executeCommand("setContext", "skein.project", true);
      await server.restart();
    }),
    vscode.commands.registerCommand("skein.showCommands", () => showCommands(context, projects.list.length > 1)),
    vscode.commands.registerCommand("skein.gettingStarted", () =>
      vscode.commands.executeCommand("workbench.action.openWalkthrough", `${context.extension.id}#skein.start`, false),
    ),
    vscode.commands.registerCommand("skein.openDocs", () => vscode.env.openExternal(vscode.Uri.parse(docs))),
    // from the tree: its item; from the editor: the item under the cursor
    vscode.commands.registerCommand("skein.editItem", async (node?: { item?: { id: string } }) => {
      const id = node?.item?.id ?? (await commands.itemAtCursor(server));
      if (id) await forms.show(id);
      else void vscode.window.showWarningMessage("skein: there is no item under the cursor");
    }),
  );
  agents.register(context, server, () => projects.list, projects.onDidChange);

  const watcher = vscode.workspace.createFileSystemWatcher("**/*.{md,toml,yaml,yml,json}");
  context.subscriptions.push(
    watcher,
    watcher.onDidCreate(refresh),
    watcher.onDidDelete(refresh),
    watcher.onDidChange(refresh),
    vscode.workspace.onDidSaveTextDocument(refresh),
    server.onDidChange(() => void projects.refresh().then(refresh)),
    vscode.workspace.onDidChangeWorkspaceFolders(async () => {
      const found = await hasProject();
      await vscode.commands.executeCommand("setContext", "skein.project", found);
      if (found && !server.running) await server.restart();
      else await projects.refresh();
    }),
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
  return { extendMarkdownIt: (md) => preview.extendMarkdownIt(md) };
}

let running: Server | undefined;

/** Skein's documentation site */
const docs = "https://skein.chasingdaylight.dev/";

/** The commands left out of the list of all commands: those that need an argument, and the list itself */
const unlisted = new Set(["skein.copyId", "skein.pickLinked", "skein.showCommands"]);

/** A list of Skein's commands, Show Coverage first, to run one; Choose Project only where there are several */
async function showCommands(context: vscode.ExtensionContext, several: boolean): Promise<void> {
  const all = (context.extension.packageJSON.contributes.commands as { command: string; title: string }[]).filter((c) => !unlisted.has(c.command) && (several || c.command !== "skein.chooseProject"));
  all.sort((a, b) => (a.command === "skein.showCoverage" ? -1 : b.command === "skein.showCoverage" ? 1 : a.title.localeCompare(b.title)));
  const picked = await vscode.window.showQuickPick(
    all.map((c) => ({ label: c.title, command: c.command })),
    { placeHolder: "Skein" },
  );
  if (picked) await vscode.commands.executeCommand(picked.command);
}

/** The active editor's file, from the project's root, with forward slashes */
function fileOfEditor(root: vscode.Uri | undefined): string | undefined {
  const doc = vscode.window.activeTextEditor?.document;
  if (!root || !doc || doc.uri.scheme !== "file") return undefined;
  const base = root.path.replace(/\/+$/, "") + "/";
  const path = doc.uri.path;
  return path.toLowerCase().startsWith(base.toLowerCase()) ? path.slice(base.length) : undefined;
}

export async function deactivate(): Promise<void> {
  await running?.stop();
}

/** Whether a folder of the workspace is in a skein project, or has one inside it */
async function hasProject(): Promise<boolean> {
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    if (folder.uri.scheme !== "file") continue;
    for (let dir = folder.uri; ; ) {
      if (await exists(vscode.Uri.joinPath(dir, ".skein", "config.toml"))) return true;
      const parent = vscode.Uri.joinPath(dir, "..");
      if (parent.path === dir.path) break;
      dir = parent;
    }
  }
  const inside = await vscode.workspace.findFiles("**/.skein/config.toml", "**/{node_modules,zig-out,zig-pkg}/**", 1);
  return inside.length > 0;
}

async function exists(uri: vscode.Uri): Promise<boolean> {
  try {
    await vscode.workspace.fs.stat(uri);
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
