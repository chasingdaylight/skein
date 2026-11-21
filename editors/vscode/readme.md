# skein for VS Code

[skein](https://github.com/chasingdaylight/skein) keeps requirements, specifications and their traceability as plain text in git. An item is a paragraph or list entry of a Markdown document with a marker, and text refers to items by ID:

```markdown
%rule[lex.comment syntax final] A line comment is not a %[lex.token]; see %[lex.space white space].

- %rule[.block syntax] A block comment starts with `/*`.
```

This extension highlights those markers and references in Markdown files, so that the item type, the ID, the category and status, and `key=value` words stand out from the prose. It also brings the `skein` program, so installing the extension is all a project's contributors need.

## What it does

- **The `skein` program:** the extension carries it for Windows, Linux, Alpine and macOS (x86_64 and arm64) and puts it on the `PATH` of new terminals in VS Code, so `skein check` works there with nothing else installed. Open a new terminal after installing.
- **Markers** (`%type[id words key=value]`): the item type, the ID, bare words and attributes each get their own color.
- **References** (`%[id]` and `%[id words]`): the ID is shown as a link target, the words as a link title.
- Nothing inside a code span or a code block is highlighted, as skein reads nothing there.

The colors come from your color theme. To change them, use `editor.tokenColorCustomizations` with the scopes `keyword.other.item-type.skein`, `entity.name.tag.item-id.skein`, `constant.language.item-word.skein`, `entity.other.attribute-name.skein` and `string.other.link.title.skein`.

## What it does not do yet

This is an early version, published as a pre-release. It does not check anything: `skein check` on the command line does. Go to definition, completion of IDs, diagnostics while typing and the views of the item graph come with the language server, which is planned.

## Settings and commands

- `skein.path`: the full path of another `skein` to use in place of the one the extension carries, for a project that pins a version of its own.
- **skein: Show Version** (Command Palette): which `skein` is in use, and its version.

## Requirements

None. On a platform the extension has no program for, install skein from its [releases](https://github.com/chasingdaylight/skein/releases) and set `skein.path`, or put it on your `PATH`; the highlighting works either way.

## Issues

Report problems and ideas at <https://github.com/chasingdaylight/skein/issues>.
