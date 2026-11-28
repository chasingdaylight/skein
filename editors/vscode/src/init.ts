// Skein: Initialize a Project...: `skein init` in a folder of the
// workspace, with a template chosen from those built into skein.

import * as vscode from "vscode";
import { parseTemplates } from "./projectmodel";
import { run } from "./run";

/** Starts a project; true when one was made */
export async function initProject(context: vscode.ExtensionContext): Promise<boolean> {
  const folder = await chooseFolder();
  if (!folder) return false;
  let listed: string;
  try {
    listed = await run(context, ["template", "list"], folder);
  } catch (err) {
    void vscode.window.showErrorMessage(err instanceof Error ? err.message : String(err));
    return false;
  }
  const none = { label: "No template", description: "the configuration alone, to fill in by hand", name: "" };
  const picked = await vscode.window.showQuickPick(
    [none, ...parseTemplates(listed).map((t) => ({ label: t.name, description: "", detail: t.description, name: t.name }))],
    { placeHolder: `A template for the project in ${folder.fsPath}`, matchOnDetail: true },
  );
  if (!picked) return false;
  try {
    const said = await run(context, picked.name ? ["init", "--template", picked.name] : ["init"], folder);
    const doc = await vscode.workspace.openTextDocument({ language: "markdown", content: said });
    await vscode.window.showTextDocument(doc, { preview: true });
    return true;
  } catch (err) {
    void vscode.window.showErrorMessage(err instanceof Error ? err.message : String(err));
    return false;
  }
}

async function chooseFolder(): Promise<vscode.Uri | undefined> {
  const folders = (vscode.workspace.workspaceFolders ?? []).filter((f) => f.uri.scheme === "file");
  if (folders.length === 1) return folders[0].uri;
  const other = { label: "Another folder...", uri: undefined as vscode.Uri | undefined };
  const picked = await vscode.window.showQuickPick([...folders.map((f) => ({ label: f.name, description: f.uri.fsPath, uri: f.uri as vscode.Uri | undefined })), other], {
    placeHolder: "The folder to start the project in",
  });
  if (!picked) return undefined;
  if (picked.uri) return picked.uri;
  const chosen = await vscode.window.showOpenDialog({ canSelectFolders: true, canSelectFiles: false, openLabel: "Start the Project Here" });
  return chosen?.[0];
}
