// Plain Node.js tests of package.json and the program it starts: every
// command is registered and has a title, every setting is under skein.*
// with a description, and the program is found where it should be.

// req: vscode.commands, vscode.server
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { test } from "node:test";
import { findProgram, programName } from "../../src/program";

const root = path.join(__dirname, "..", "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const source = ["commands.ts", "agents.ts"].map((f) => fs.readFileSync(path.join(root, "src", f), "utf8")).join("\n");

test("every command has a title and is registered", () => {
  const commands: { command: string; title: string; category: string }[] = manifest.contributes.commands;
  assert.ok(commands.length >= 8);
  for (const c of commands) {
    assert.ok(c.title, `${c.command} has a title`);
    assert.equal(c.category, "skein");
    assert.ok(source.includes(`command("${c.command}"`) || source.includes(`registerCommand("${c.command}"`), `${c.command} is registered`);
  }
  // and every command named in a menu exists
  const names = new Set(commands.map((c) => c.command));
  for (const [menu, entries] of Object.entries(manifest.contributes.menus as Record<string, { command: string }[]>)) {
    for (const e of entries) assert.ok(names.has(e.command), `${e.command} of ${menu} exists`);
  }
});

test("Trace is on the editor's and the tree's context menus", () => {
  const menus = manifest.contributes.menus;
  assert.ok(menus["editor/context"].some((e: { command: string }) => e.command === "skein.trace"));
  assert.ok(menus["view/item/context"].some((e: { command: string }) => e.command === "skein.trace"));
});

test("every setting is under skein.* and has a description", () => {
  const properties: Record<string, { markdownDescription?: string; description?: string }> = manifest.contributes.configuration.properties;
  for (const [name, p] of Object.entries(properties)) {
    assert.ok(name.startsWith("skein."), name);
    assert.ok(p.markdownDescription || p.description, `${name} has a description`);
  }
});

test("the program: the one skein.path names, else the one in bin/", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "skein-unit-"));
  assert.equal(findProgram("", dir), undefined);
  fs.mkdirSync(path.join(dir, "bin"));
  const bundled = path.join(dir, "bin", programName());
  fs.writeFileSync(bundled, "");
  assert.equal(findProgram("", dir), bundled);
  const other = path.join(dir, "other");
  assert.equal(findProgram(other, dir), undefined);
  fs.writeFileSync(other, "");
  assert.equal(findProgram(` ${other} `, dir), other);
  assert.equal(programName("win32"), "skein.exe");
  assert.equal(programName("linux"), "skein");
});
