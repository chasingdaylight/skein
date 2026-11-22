# Changelog

## 0.1.1 (unreleased)

- The extension carries the `skein` program for its platform and puts it on the `PATH` of new terminals, so `skein check` works there with nothing else installed. There is a package for Windows, Linux, Alpine and macOS, each for x86_64 and arm64; other platforms get the package without a program.
- The setting `skein.path` names another `skein` to use, and the command "skein: Show Version" says which one is in use.
- The extension has an icon: the skein logo.
- The extension starts skein's language server (`skein lsp`) in a skein project: the problems of `skein check` in the Problems panel, with quick fixes; go to definition, references, hover, completion and rename of IDs; and code lenses above items with their links and **Trace**.
- **skein Items**, a tree in the Explorer of the items by source and file; the **Trace** and **Coverage** views, in the colors of the theme; the coverage in the status bar.
- Commands **Trace**, **Show Coverage**, **Go to Item...**, **Refresh Items** and **Restart the Language Server**; settings `skein.codeLens.enabled`, `skein.statusBar.coverage` and `skein.trace.server`.

## 0.1.0

- Highlighting of skein's item markers (`%type[id words key=value]`) and references (`%[id]`, `%[id words]`) in Markdown files.
