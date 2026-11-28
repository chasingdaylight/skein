// The coverage of the project in the status bar (skein.statusBar.coverage),
// which opens the list of Skein's commands, Show Coverage first.

import * as vscode from "vscode";
import { Server } from "./client";
import { coverageText } from "./model";

export class Status {
  private readonly item = vscode.window.createStatusBarItem("skein.coverage", vscode.StatusBarAlignment.Left, 10);

  constructor(private readonly server: Server) {
    this.item.name = "Skein Coverage";
    this.item.command = "skein.showCommands";
  }

  /** The project's name, shown where the workspace has several */
  project: string | undefined;

  dispose(): void {
    this.item.dispose();
  }

  async refresh(): Promise<void> {
    if (!vscode.workspace.getConfiguration("skein").get<boolean>("statusBar.coverage", true) || !this.server.running) {
      this.item.hide();
      return;
    }
    const result = await this.server.request<{ covered: number; total: number }>("skein/coverage");
    if (!result) {
      this.item.hide();
      return;
    }
    const { text, tooltip } = coverageText(result.covered, result.total, this.project);
    this.item.text = text;
    this.item.tooltip = `${tooltip}. Click for Skein's commands.`;
    this.item.show();
  }
}
