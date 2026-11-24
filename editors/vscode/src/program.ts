// Finding the `skein` program: the one `skein.path` names, else the one
// the package carries in bin/. No VS Code here, so that it is tested with
// Node alone.

import * as fs from "node:fs";
import * as path from "node:path";

export function programName(platform: string = process.platform): string {
  return platform === "win32" ? "skein.exe" : "skein";
}

/** The program to use, or undefined when there is none */
export function findProgram(configured: string, extensionPath: string, platform: string = process.platform): string | undefined {
  const named = configured.trim();
  if (named) return fs.existsSync(named) ? named : undefined;
  const bundled = path.join(extensionPath, "bin", programName(platform));
  return fs.existsSync(bundled) ? bundled : undefined;
}

/** The arguments of `skein agents` for the settings skein.agents.file and skein.agents.skill */
export function agentsArgs(file: string, skill: boolean): string[] {
  const args = ["agents"];
  if (skill) args.push("--skill");
  if (file.trim()) args.push("--file", file.trim());
  return args;
}

/** Makes a program the package carries executable: a VSIX keeps no file modes */
export function ensureExecutable(program: string): void {
  if (process.platform === "win32") return;
  try {
    const mode = fs.statSync(program).mode;
    if ((mode & 0o111) === 0) fs.chmodSync(program, mode | 0o755);
  } catch {
    // starting it says what is wrong
  }
}
