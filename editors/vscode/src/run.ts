// Running the skein program from the extension: the one skein.path names,
// else the one the package carries, in the root of the current project.

import { execFile } from "node:child_process";
import * as vscode from "vscode";
import { findProgram } from "./program";

export function programOf(context: vscode.ExtensionContext): string | undefined {
  return findProgram(vscode.workspace.getConfiguration("skein").get<string>("path", ""), context.extensionPath);
}

/** Where skein runs: the root of the current project (projects.ts), else the first folder */
let rootOf: () => vscode.Uri | undefined = () => vscode.workspace.workspaceFolders?.[0]?.uri;

export function setRoot(root: () => vscode.Uri | undefined): void {
  rootOf = root;
}

/** Runs skein in the current project; what it printed, or an error with it */
export function run(context: vscode.ExtensionContext, args: string[]): Promise<string> {
  const program = programOf(context);
  const root = rootOf();
  if (!program || !root) return Promise.reject(new Error("skein: no skein program, or no folder open"));
  return new Promise((resolve, reject) => {
    execFile(program, args, { cwd: root.fsPath, timeout: 60_000, maxBuffer: 16 << 20 }, (error, stdout, stderr) => {
      if (error) reject(new Error((stderr || stdout || error.message).trim()));
      else resolve(stdout || stderr);
    });
  });
}
