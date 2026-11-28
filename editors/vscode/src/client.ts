// The language client: starts `skein lsp` for the projects of the
// workspace's folders, and stops and restarts it. Everything the server
// can do (diagnostics, definition, references, hover, completion, rename,
// code lenses, quick fixes) comes through it.

import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions } from "vscode-languageclient/node";
import { ensureExecutable, findProgram } from "./program";

export class Server {
  private client: LanguageClient | undefined;
  /** serializes starts and stops */
  private pending: Promise<void> = Promise.resolve();
  private readonly changed = new vscode.EventEmitter<void>();
  /** fires once the server has started, and once it has stopped */
  readonly onDidChange = this.changed.event;
  /** the URI of the project the views are about (projects.ts) */
  projectOf: () => string | undefined = () => undefined;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly output: vscode.LogOutputChannel,
  ) {
    context.subscriptions.push(this.changed);
  }

  get running(): LanguageClient | undefined {
    return this.client;
  }

  /** A request of skein's own; undefined when no server runs or it fails */
  async request<T>(method: string, params: object = {}): Promise<T | undefined> {
    const c = this.client;
    if (!c) return undefined;
    try {
      return await c.sendRequest<T>(method, this.withProject(params));
    } catch (err) {
      this.output.warn(`${method}: ${String(err)}`);
      void vscode.window.showWarningMessage(errorMessage(err));
      return undefined;
    }
  }

  /** `params` naming the current project, unless they name a document or a project */
  withProject(params: object): object {
    if ("project" in params || "uri" in params || "textDocument" in params) return params;
    const project = this.projectOf();
    return project ? { ...params, project } : params;
  }

  restart(): Promise<void> {
    this.pending = this.pending.then(async () => {
      await this.stopNow();
      await this.startNow();
      this.changed.fire();
    });
    return this.pending;
  }

  stop(): Promise<void> {
    this.pending = this.pending.then(() => this.stopNow());
    return this.pending;
  }

  private async stopNow(): Promise<void> {
    const c = this.client;
    this.client = undefined;
    void vscode.commands.executeCommand("setContext", "skein.running", false);
    if (!c) return;
    try {
      await c.stop();
    } catch (err) {
      this.output.warn(`stopping the language server: ${String(err)}`);
    }
  }

  private async startNow(): Promise<void> {
    if (!vscode.workspace.isTrusted) return;
    const folder = vscode.workspace.workspaceFolders?.[0];
    if (!folder || folder.uri.scheme !== "file") return;
    const configured = vscode.workspace.getConfiguration("skein").get<string>("path", "");
    const command = findProgram(configured, this.context.extensionPath);
    if (!command) {
      const message = configured.trim()
        ? `skein: there is no file '${configured}' (the setting skein.path).`
        : "skein: this package of the extension carries no skein program for this platform. Install skein and set skein.path.";
      this.output.error(message);
      void vscode.window.showErrorMessage(message, "Open Settings").then((choice) => {
        if (choice) void vscode.commands.executeCommand("workbench.action.openSettings", "skein.path");
      });
      return;
    }
    if (command.startsWith(this.context.extensionPath)) ensureExecutable(command);
    this.output.info(`Starting ${command} lsp`);
    const executable = { command, args: ["lsp"], options: { cwd: folder.uri.fsPath } };
    const serverOptions: ServerOptions = { run: executable, debug: executable };
    const clientOptions: LanguageClientOptions = {
      // documents, item files, and the code and tests that cite items; the
      // server leaves alone what is not of the project
      documentSelector: [{ scheme: "file" }],
      synchronize: {
        fileEvents: vscode.workspace.createFileSystemWatcher("**/*.{md,toml,yaml,yml,json}"),
      },
      middleware: {
        provideCodeLenses: (document, token, next) =>
          vscode.workspace.getConfiguration("skein").get<boolean>("codeLens.enabled", true) ? next(document, token) : [],
      },
      outputChannel: this.output,
    };
    const c = new LanguageClient("skein", "Skein Language Server", serverOptions, clientOptions);
    try {
      await c.start();
      this.client = c;
      await vscode.commands.executeCommand("setContext", "skein.running", true);
    } catch (err) {
      this.output.error(`starting ${command}: ${String(err)}`);
      void vscode.window.showErrorMessage(`skein: the language server failed to start: ${String(err)}`);
    }
  }
}

function errorMessage(err: unknown): string {
  if (err && typeof err === "object" && "message" in err) return String((err as { message: unknown }).message);
  return String(err);
}
