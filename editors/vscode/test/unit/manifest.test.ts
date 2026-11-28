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
const source = ["commands.ts", "agents.ts", "extension.ts"].map((f) => fs.readFileSync(path.join(root, "src", f), "utf8")).join("\n");

test("every command has a title and is registered", () => {
  const commands: { command: string; title: string; category: string }[] = manifest.contributes.commands;
  assert.ok(commands.length >= 8);
  for (const c of commands) {
    assert.ok(c.title, `${c.command} has a title`);
    assert.equal(c.category, "Skein");
    assert.ok(source.includes(`command("${c.command}"`) || source.includes(`registerCommand("${c.command}"`), `${c.command} is registered`);
  }
  // and every command or submenu named in a menu exists
  const names = new Set(commands.map((c) => c.command));
  const submenus = new Set((manifest.contributes.submenus as { id: string }[]).map((s) => s.id));
  for (const [menu, entries] of Object.entries(manifest.contributes.menus as Record<string, { command?: string; submenu?: string }[]>)) {
    for (const e of entries) {
      if (e.submenu) assert.ok(submenus.has(e.submenu), `the submenu ${e.submenu} of ${menu} exists`);
      else assert.ok(names.has(e.command!), `${e.command} of ${menu} exists`);
    }
  }
});

// req: vscode.discoverable
test("the Items view is in Skein's own view container, with its actions on its title bar", () => {
  const container = manifest.contributes.viewsContainers.activitybar.find((c: { id: string }) => c.id === "skein");
  assert.ok(container && fs.existsSync(path.join(root, container.icon)));
  assert.ok(manifest.contributes.views.skein.some((v: { id: string }) => v.id === "skein.items"));
  const title = manifest.contributes.menus["view/title"].map((e: { command: string }) => e.command);
  for (const c of ["skein.newItem", "skein.openItem", "skein.showCoverage", "skein.showPlan", "skein.showGraph", "skein.refreshItems"]) assert.ok(title.includes(c), c);
  assert.ok(manifest.contributes.viewsWelcome.some((w: { view: string }) => w.view === "skein.items"));
});

test("a Markdown editor of a project has a Skein menu on its title bar", () => {
  const entry = manifest.contributes.menus["editor/title"].find((e: { submenu?: string }) => e.submenu === "skein.editor");
  assert.ok(entry && entry.when.includes("resourceLangId == markdown"));
  const inside = manifest.contributes.menus["skein.editor"].map((e: { command: string }) => e.command);
  for (const c of ["skein.newItemHere", "skein.editItem", "skein.trace", "skein.showCoverage", "skein.showCommands"]) assert.ok(inside.includes(c), c);
});

test("the walkthrough's steps have their pages, and the package carries them", () => {
  const ignore = fs.readFileSync(path.join(root, ".vscodeignore"), "utf8");
  assert.ok(ignore.includes("!media/walkthrough/**") && ignore.includes("!media/skein.svg"));
  const walk = manifest.contributes.walkthroughs.find((w: { id: string }) => w.id === "skein.start");
  assert.ok(walk.steps.length >= 5);
  for (const step of walk.steps) {
    assert.ok(fs.existsSync(path.join(root, step.media.markdown)), step.media.markdown);
    // a step's description shows code spans as written
    assert.ok(!step.description.includes("`"), step.id);
  }
  assert.ok(source.includes(`#skein.start`));
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
