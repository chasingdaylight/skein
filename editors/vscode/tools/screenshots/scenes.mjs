// The screenshots: each scene sets VS Code up as a page of the docs shows
// it, and says which part of the window to keep (all of it when no clip).
// The rover scenes run in the quickstart's project, the plan in station's.

/** Opens a file by its path in the project, at a line when one is given */
async function open(v, file, line) {
  await v.key("p", 2); // ctrl+p
  await v.type(file);
  await v.sleep(900);
  await v.key("Enter");
  await v.sleep(1500);
  if (line) {
    await v.key("g", 2); // ctrl+g
    await v.type(String(line));
    await v.key("Enter");
    await v.sleep(500);
  }
}

/** The Skein view in the side bar */
async function skeinView(v) {
  const shown = await v.where(".activitybar .action-item.checked a", "Skein");
  if (!shown) await v.click(".activitybar .action-item a", "Skein");
  await v.sleep(1200);
}

export const rover = [
  {
    name: "items",
    async run(v) {
      await skeinView(v);
      await v.click(".pane-body .monaco-list-row", "srs.md");
      await v.sleep(800);
      await open(v, "docs/srs.md", 20);
    },
  },
  {
    name: "editor-menu",
    async run(v) {
      await open(v, "docs/srs.md", 20);
      await v.click(".editor-actions .action-item a", "Skein");
      await v.sleep(800);
      return { x: 640, y: 30, width: 640, height: 330 };
    },
  },
  {
    name: "hover",
    async run(v) {
      await open(v, "docs/srs.md", 20);
      // the ID in SRS-001's marker, not the mention in the narrative above
      const at = await v.evaluate(`(() => {
        const line = [...document.querySelectorAll(".view-line")].find((l) => l.textContent.includes("%requirement[SRS-001"));
        const span = [...line.querySelectorAll("span span")].find((s) => s.textContent.includes("SRS-001"));
        const r = span.getBoundingClientRect();
        return { x: r.x + 20, y: r.y + r.height / 2 };
      })()`);
      await v.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: at.x, y: at.y });
      await v.sleep(2000);
      return { x: 300, y: 250, width: 980, height: 420 };
    },
  },
  {
    name: "completion",
    async run(v) {
      // the blank line after SRS-002
      await open(v, "docs/srs.md", 23);
      await v.key("Enter");
      await v.type("%requirement[SRS-003 ");
      await v.key(" ", 2); // ctrl+space
      await v.sleep(1500);
      return { x: 300, y: 330, width: 980, height: 400 };
    },
    async after(v) {
      await v.key("Escape");
      await v.command("File: Revert File", 800);
    },
  },
  {
    name: "preview",
    async run(v) {
      await open(v, "docs/srs.md", 16);
      await v.command("Markdown: Open Preview to the Side", 4000);
    },
  },
  {
    name: "form-new",
    async run(v) {
      await open(v, "docs/srs.md", 22);
      await v.command("Skein: New Item in This Document", 3000);
    },
  },
  {
    name: "form-edit",
    async run(v) {
      await open(v, "docs/srs.md", 20);
      await v.command("Skein: Edit Item", 3000);
    },
  },
  {
    name: "trace",
    async run(v) {
      await open(v, "docs/srs.md", 20);
      await v.command("Skein: Trace", 3000);
    },
  },
  {
    name: "coverage",
    async run(v) {
      await v.command("Skein: Show Coverage", 3500);
    },
  },
  {
    name: "graph",
    async run(v) {
      await v.command("Skein: Show Graph", 6000);
      // the project's own items, SRS-001 chosen: its trace beside the graph
      await v.inWebview(`(d) => {
        const source = d.querySelectorAll("select")[1];
        source.value = "docs";
        source.dispatchEvent(new Event("change", { bubbles: true }));
        [...d.querySelectorAll("button")].find((b) => b.textContent === "Fit").click();
        const name = [...d.querySelectorAll("svg text")].find((t) => t.textContent === "SRS-001");
        name.closest("g").dispatchEvent(new MouseEvent("click", { bubbles: true }));
      }`);
      await v.sleep(1500);
    },
  },
  {
    name: "commands",
    async run(v) {
      await open(v, "docs/srs.md", 20);
      await v.click(".statusbar-item", "%");
      await v.sleep(900);
    },
  },
  {
    name: "walkthrough",
    async run(v) {
      await v.command("Skein: Get Started", 3000);
    },
  },
  {
    name: "problems",
    async run(v) {
      // a reference to an item there is not, in SRS-002's paragraph
      await open(v, "docs/srs.md", 23);
      await v.type("See %[SRS-099] for the brakes.");
      await v.key("s", 2); // ctrl+s
      await v.sleep(2500);
      await v.command("View: Focus Problems", 1500);
    },
    async after(v) {
      // main.mjs puts the file back as it was; the editor reads it again
      await v.command("View: Close Panel", 800);
    },
  },
];

export const station = [
  {
    name: "plan",
    async run(v) {
      await v.command("Skein: Show Plan", 5000);
    },
  },
  {
    name: "board",
    async run(v) {
      await v.command("Skein: Show Plan", 5000);
      await v.inWebview(`(d) => [...d.querySelectorAll("button")].find((b) => b.textContent === "Board").click()`);
      await v.sleep(1000);
    },
  },
];

/** Back to no editors open, nothing over the window */
export async function reset(v) {
  await v.key("Escape");
  await v.key("Escape");
  await v.command("View: Close All Editors", 800);
}
