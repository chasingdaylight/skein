# skein for VS Code

[skein](https://github.com/chasingdaylight/skein) keeps requirements, specifications and their traceability as plain text in git. An item is a paragraph or list entry of a Markdown document with a marker, and text refers to items by ID:

```markdown
%rule[lex.comment syntax final] A line comment is not a %[lex.token]; see %[lex.space white space].

- %rule[.block syntax] A block comment starts with `/*`.
```

This extension brings the `skein` program and its language server into VS Code: the problems of `skein check` as you save, go to definition, references, completion and rename of IDs, the items in a tree, an item's trace, and the project's coverage. Installing the extension is all a project's contributors need.

## What it does

- **The language server:** in a folder with a skein project (`.skein/config.toml`), the extension starts `skein lsp`. The problems of `skein check` are in the Problems panel, updated when a file is saved, with quick fixes where skein knows what was meant: the ID an item has now for a former one, and the word closest to a misspelled ID, category, status, attribute or link type. Go to definition, find references, hover, completion and rename (which does what `skein move` does) work on IDs wherever they are written.
- **Code lenses:** above each item, its links (those it has and those that point to it), which offer the items they lead to, and **Trace**.
- **skein Items:** a tree in the Explorer of every item, by source and file, with its type, category and status, and its parts under it. Choosing one opens it at its marker; **Trace** and **Copy ID** are on its context menu.
- **Trace:** an item's trace in a view beside the editor: its links both ways, what it refers to and what refers to it, citations, approvals, test results, and all above and below it. Its links open the items and places in the editor. Open it from a code lens, the tree, the editor's context menu, or **skein: Trace** in the Command Palette (the item under the cursor, or one you choose).
- **Forms:** **skein: New Item...** and **Edit Item...** (on the editor's and the tree's context menus) open a form of the item's category, status, attributes and links, as its type allows, with the items a link may point to offered. Saving writes the item's marker or front matter; a new item gets its own file, or goes at the end of the document chosen.
- **Graph:** **skein: Show Graph** draws the network of items and their links, each item above those that link to it, with suspect links and links never reviewed marked. Drag to pan, and zoom with the wheel, a pinch, the buttons at the top right (zoom in, zoom out, fit, 100%) or the keys `+`, `-`, `f` and `0`; search, and filter by item type, link type, profile and source. Choosing an item shows its trace beside the graph; it and the item's context menu have Open, Trace, Copy ID, Review its links and Approve.
- **Plan:** for a project with work items (item types with `[planning]`), **skein: Show Plan** opens a Gantt chart of the schedule and a board by status. Drag a bar to move an item, its right end to change its length, or a card to another status: the change is written into the item's marker or front matter, and the stored schedule (`.skein/schedule.toml`) follows. A float item moved by hand becomes fixed.
- **AI agents:** VS Code's agents (Copilot's agent mode and others) get skein's tools through `skein mcp`, which the extension offers to VS Code's MCP support: finding and tracing items, `check`, `coverage`, `impact`, and the editing commands. In chat, `#skeinItem` brings in the item under the cursor with everything linked to it. **skein: Write Agent Instructions** writes what agents should know of the project's skein documents into `AGENTS.md` (or `CLAUDE.md`).
- **Coverage:** the coverage page, in a view, and the share of what is expected that is covered in the status bar, which opens the view.
- **The `skein` program:** the extension carries it for Windows, Linux, Alpine and macOS (x86_64 and arm64) and puts it on the `PATH` of new terminals in VS Code, so `skein check` works there with nothing else installed. Open a new terminal after installing.
- **Markdown preview:** VS Code's preview of a saved document shows it as `skein render` writes it: markers as the item's ID with its category and status, references as links to the items, unresolved references marked, and generated pages (lists, matrices, coverage, Gantt charts) in place. While a document has unsaved changes, the preview shows it as written.
- **Highlighting:** in Markdown, markers (`%type[id words key=value]`) and references (`%[id]`, `%[id words]`) stand out from the prose; nothing inside a code span or a code block is highlighted, as skein reads nothing there.

The colors and fonts of the views come from your color theme. To change those of the highlighting, use `editor.tokenColorCustomizations` with the scopes `keyword.other.item-type.skein`, `entity.name.tag.item-id.skein`, `constant.language.item-word.skein`, `entity.other.attribute-name.skein` and `string.other.link.title.skein`.

## Commands

In the Command Palette, under **skein**: **Trace**, **Show Coverage**, **Show Plan**, **Show Graph**, **New Item...**, **Edit Item...**, **Write Agent Instructions**, **Go to Item...**, **Refresh Items**, **Restart the Language Server** and **Show Version**.

## Settings

- `skein.path`: the full path of another `skein` to use in place of the one the extension carries, for a project that pins a version of its own. A change restarts the language server.
- `skein.codeLens.enabled`: the code lenses above items (on by default).
- `skein.statusBar.coverage`: the coverage in the status bar (on by default).
- `skein.mcp.enabled`: offer `skein mcp` to VS Code's agents (on by default).
- `skein.agents.file`, `skein.agents.skill`: where **Write Agent Instructions** writes, and whether as a skill file.
- `skein.trace.server`: log the messages to and from the language server in the output channel **skein Language Server**.

## Requirements

None. On a platform the extension has no program for, install skein from its [releases](https://github.com/chasingdaylight/skein/releases) and set `skein.path`; the highlighting works either way. In an untrusted workspace, the language server is not started.

## Issues

Report problems and ideas at <https://github.com/chasingdaylight/skein/issues>.
