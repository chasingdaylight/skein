// Takes the screenshots of the VS Code extension for the docs, in VS Code's
// Light Modern and Dark Modern themes: docs/img/vscode/NAME-light.png and
// NAME-dark.png, which the docs show as one <picture> (#310).
//
//   npm run build   (in editors/vscode), then from the repository's root:
//   node editors/vscode/tools/screenshots/main.mjs --code PATH/Code.exe [--skein PATH] [--only NAME,...]
//
// --code is a portable VS Code (its folder has a data/ directory), used for
// nothing else: the extension is installed into it, its settings are
// written, and it is opened on two projects made fresh in --work (default:
// a directory beside it), driven over its debugging port. Needs git and a
// skein that is built (zig build); Node.js 22 or later.

import { spawn } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { connect } from "./cdp.mjs";
import * as projects from "./projects.mjs";
import * as scenes from "./scenes.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const extension = resolve(here, "..", "..");
const repo = resolve(extension, "..", "..");
const port = 9333;

function args() {
  const out = {};
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 2) out[argv[i].replace(/^--/, "")] = argv[i + 1];
  if (!out.code) throw new Error("--code PATH: the portable VS Code's program");
  out.skein ??= join(repo, "zig-out", "bin", process.platform === "win32" ? "skein.exe" : "skein");
  out.out ??= join(repo, "docs", "img", "vscode");
  out.work ??= join(dirname(out.code), "..", "screenshot-projects");
  out.only = out.only ? out.only.split(",") : null;
  // --keep 1: VS Code stays open after the scenes, to look at it
  if (out.keep !== undefined && !out.only) throw new Error("--keep goes with --only");
  return out;
}

/** The extension as its package holds it (.vscodeignore), with skein, in the portable VS Code */
function install(code, skein) {
  const manifest = JSON.parse(readFileSync(join(extension, "package.json"), "utf8"));
  const exts = join(dirname(code), "data", "extensions");
  const target = join(exts, `${manifest.publisher}.${manifest.name}-${manifest.version}`);
  rmSync(target, { recursive: true, force: true });
  for (const f of ["package.json", "dist", "media", "syntaxes", "icon.png", "readme.md", "CHANGELOG.md", "LICENSE"]) {
    if (!existsSync(join(extension, f))) throw new Error(`editors/vscode/${f} is missing: run npm run build`);
    cpSync(join(extension, f), join(target, f), { recursive: true });
  }
  mkdirSync(join(target, "bin"), { recursive: true });
  cpSync(skein, join(target, "bin", process.platform === "win32" ? "skein.exe" : "skein"));
  // VS Code loads the extensions its list names, as an install would write it
  const relative = `${manifest.publisher}.${manifest.name}-${manifest.version}`;
  const entry = {
    identifier: { id: `${manifest.publisher}.${manifest.name}` },
    version: manifest.version,
    location: { $mid: 1, path: pathToFileURL(target).pathname, scheme: "file" },
    relativeLocation: relative,
    metadata: { installedTimestamp: Date.now(), source: "vsix" },
  };
  writeFileSync(join(exts, "extensions.json"), JSON.stringify([entry]));
}

function settings(code, theme) {
  const file = join(dirname(code), "data", "user-data", "User", "settings.json");
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(
    file,
    JSON.stringify(
      {
        "workbench.colorTheme": theme === "dark" ? "Default Dark Modern" : "Default Light Modern",
        "workbench.startupEditor": "none",
        "workbench.tips.enabled": false,
        "workbench.secondarySideBar.defaultVisibility": "hidden",
        "workbench.welcomePage.walkthroughs.openOnInstall": false,
        "window.restoreWindows": "none",
        "window.commandCenter": true,
        "update.mode": "none",
        "telemetry.telemetryLevel": "off",
        "extensions.autoCheckUpdates": false,
        "extensions.autoUpdate": false,
        "security.workspace.trust.enabled": false,
        "chat.disableAIFeatures": true,
        "chat.commandCenter.enabled": false,
        "editor.minimap.enabled": false,
        "git.enabled": false,
        "github.gitAuthentication": false,
      },
      null,
      2,
    ),
  );
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** VS Code on `folder`, once its window is up and Skein's server has answered */
async function launch(code, folder, keep) {
  const child = spawn(code, [folder, `--remote-debugging-port=${port}`, "--new-window", "--skip-welcome", "--skip-release-notes", "--disable-workspace-trust"], {
    stdio: "ignore",
    // kept open: not ended with this script
    detached: keep,
  });
  if (keep) child.unref();
  for (let i = 0; i < 60; i++) {
    await sleep(1000);
    try {
      const v = await connect(port);
      await v.size(1280, 800);
      // the coverage in the status bar: the server has answered
      for (let j = 0; j < 60; j++) {
        if (await v.evaluate(`[...document.querySelectorAll('.statusbar-item')].some((e) => /%/.test(e.textContent))`)) return { v, child };
        await sleep(1000);
      }
      throw new Error("Skein's language server did not answer");
    } catch (err) {
      if (String(err).includes("did not answer")) throw err;
    }
  }
  throw new Error("VS Code did not start");
}

async function quit(child) {
  try {
    const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
    const ws = new WebSocket(version.webSocketDebuggerUrl);
    await new Promise((r) => (ws.onopen = r));
    ws.send(JSON.stringify({ id: 1, method: "Browser.close" }));
  } catch {
    child.kill();
  }
  await new Promise((r) => (child.exitCode !== null ? r() : child.once("exit", r)));
  await sleep(1500);
}

async function take(o, theme, folder, list) {
  const chosen = list.filter((s) => !o.only || o.only.includes(s.name));
  if (chosen.length === 0) return;
  const { v, child } = await launch(o.code, folder, o.keep !== undefined);
  try {
    for (const scene of chosen) {
      projects.restore(folder);
      await scenes.reset(v);
      const clip = await scene.run(v);
      const file = join(o.out, `${scene.name}-${theme}.png`);
      await v.shot(file, clip);
      console.log(file);
      if (scene.after) await scene.after(v);
    }
  } finally {
    v.close();
    if (o.keep === undefined) await quit(child);
  }
}

const o = args();
install(o.code, o.skein);
mkdirSync(o.out, { recursive: true });
const rover = projects.rover(join(o.work, "rover"), o.skein);
const station = projects.station(join(o.work, "station"), o.skein);
for (const theme of o.keep === undefined ? ["light", "dark"] : ["light"]) {
  settings(o.code, theme);
  await take(o, theme, rover, scenes.rover);
  await take(o, theme, station, scenes.station);
}
process.exit(0);
