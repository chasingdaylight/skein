// Which project the views are about, where the workspace has several: the
// project of the active editor's file, else the one last chosen or last
// active, else the first. The requests of the views name it (`project`).

import * as vscode from "vscode";
import { Server } from "./client";
import { labelOf, ProjectInfo, projectOf } from "./projectmodel";

export class Projects {
  private all: ProjectInfo[] = [];
  private chosen: ProjectInfo | undefined;
  private readonly changed = new vscode.EventEmitter<void>();
  /** fires when the current project changes */
  readonly onDidChange = this.changed.event;

  constructor(private readonly server: Server) {
    server.projectOf = () => this.chosen?.uri;
  }

  dispose(): void {
    this.changed.dispose();
  }

  get list(): ProjectInfo[] {
    return this.all;
  }

  get current(): ProjectInfo | undefined {
    return this.chosen;
  }

  /** The label of the current project, where there are several; else undefined */
  get label(): string | undefined {
    return this.all.length > 1 && this.chosen ? labelOf(this.all, this.chosen) : undefined;
  }

  /** Asks the server for the projects again */
  async refresh(): Promise<void> {
    this.all = (await this.server.request<ProjectInfo[] | null>("skein/projects")) ?? [];
    await vscode.commands.executeCommand("setContext", "skein.projects", this.all.length > 1);
    const kept = this.chosen && this.all.find((p) => p.uri === this.chosen!.uri);
    this.set(this.fromEditor() ?? kept ?? this.all[0]);
  }

  /** Follows the active editor into the project of its file */
  follow(): void {
    const p = this.fromEditor();
    if (p) this.set(p);
  }

  /** Lets the person choose the project the views are about */
  async choose(): Promise<void> {
    if (this.all.length === 0) await this.refresh();
    const picked = await vscode.window.showQuickPick(
      this.all.map((p) => ({ label: labelOf(this.all, p), description: vscode.Uri.parse(p.uri).fsPath, project: p })),
      { placeHolder: "The Skein project the views show" },
    );
    if (picked) this.set(picked.project);
  }

  /** The root of the current project, for paths from it */
  root(): vscode.Uri | undefined {
    return this.chosen ? vscode.Uri.parse(this.chosen.uri) : vscode.workspace.workspaceFolders?.[0]?.uri;
  }

  private fromEditor(): ProjectInfo | undefined {
    const doc = vscode.window.activeTextEditor?.document;
    if (!doc || doc.uri.scheme !== "file") return undefined;
    return projectOf(this.all, doc.uri.toString(), process.platform === "win32" || process.platform === "darwin");
  }

  private set(p: ProjectInfo | undefined): void {
    if (p?.uri === this.chosen?.uri) return;
    this.chosen = p;
    this.changed.fire();
  }
}
