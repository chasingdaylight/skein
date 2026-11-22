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
- **Coverage:** the coverage page, in a view, and the share of what is expected that is covered in the status bar, which opens the view.
- **The `skein` program:** the extension carries it for Windows, Linux, Alpine and macOS (x86_64 and arm64) and puts it on the `PATH` of new terminals in VS Code, so `skein check` works there with nothing else installed. Open a new terminal after installing.
- **Highlighting:** in Markdown, markers (`%type[id words key=value]`) and references (`%[id]`, `%[id words]`) stand out from the prose; nothing inside a code span or a code block is highlighted, as skein reads nothing there.

The colors and fonts of the views come from your color theme. To change those of the highlighting, use `editor.tokenColorCustomizations` with the scopes `keyword.other.item-type.skein`, `entity.name.tag.item-id.skein`, `constant.language.item-word.skein`, `entity.other.attribute-name.skein` and `string.other.link.title.skein`.

## Commands

In the Command Palette, under **skein**: **Trace**, **Show Coverage**, **Go to Item...**, **Refresh Items**, **Restart the Language Server** and **Show Version**.

## Settings

- `skein.path`: the full path of another `skein` to use in place of the one the extension carries, for a project that pins a version of its own. A change restarts the language server.
- `skein.codeLens.enabled`: the code lenses above items (on by default).
- `skein.statusBar.coverage`: the coverage in the status bar (on by default).
- `skein.trace.server`: log the messages to and from the language server in the output channel **skein Language Server**.

## Requirements

None. On a platform the extension has no program for, install skein from its [releases](https://github.com/chasingdaylight/skein/releases) and set `skein.path`; the highlighting works either way. In an untrusted workspace, the language server is not started.

## Issues

Report problems and ideas at <https://github.com/chasingdaylight/skein/issues>.
