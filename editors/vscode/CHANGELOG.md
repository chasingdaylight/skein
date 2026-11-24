# Changelog

## 0.1.1 (unreleased)

- The extension carries the `skein` program for its platform and puts it on the `PATH` of new terminals, so `skein check` works there with nothing else installed. There is a package for Windows, Linux, Alpine and macOS, each for x86_64 and arm64; other platforms get the package without a program.
- The setting `skein.path` names another `skein` to use, and the command "skein: Show Version" says which one is in use.
- The extension has an icon: the skein logo.
- The extension starts skein's language server (`skein lsp`) in a skein project: the problems of `skein check` in the Problems panel, with quick fixes; go to definition, references, hover, completion and rename of IDs; and code lenses above items with their links and **Trace**.
- **skein Items**, a tree in the Explorer of the items by source and file; the **Trace** and **Coverage** views, in the colors of the theme; the coverage in the status bar.
- **Plan**: a Gantt chart and a board of the work items, whose bars and cards are dragged to change an item's dates or status, written into its file.
- For VS Code's AI agents: `skein mcp` offered to VS Code's MCP support, the chat tool `#skeinItem`, and **Write Agent Instructions**; settings `skein.mcp.enabled`, `skein.agents.file`, `skein.agents.skill`.
- **New Item** and **Edit Item**: a form of an item's category, status, attributes and links, written into its file.
- **Graph**: the network of items and links, with search, filters, an item's trace beside it and the actions on items.
- VS Code's Markdown preview shows a saved document as `skein render` writes it.
- Highlighting, tuned on a real specification in the built-in themes: the marker of a tested example on its fence's line is highlighted; a marker only at the start of a line, a list entry or a quote, where Skein reads one; an item's ID in a color of its own (`entity.name.function.item-id.skein`, which was `entity.name.tag.item-id.skein`), apart from the item type's.
- Commands **Trace**, **Show Coverage**, **Show Plan**, **Go to Item...**, **Refresh Items** and **Restart the Language Server**; settings `skein.codeLens.enabled`, `skein.statusBar.coverage` and `skein.trace.server`.

## 0.1.0

- Highlighting of skein's item markers (`%type[id words key=value]`) and references (`%[id]`, `%[id words]`) in Markdown files.
