# Skein

Skein keeps requirements, specifications and their traceability as plain text in git. An item is a paragraph of a Markdown document, or a file of its own, with a stable ID, a type and typed links to other items. Code and tests cite the items they implement and check. Skein reads all of it and answers the questions a project keeps asking: is everything consistent, what does this rest on, what is not tested yet, what changed, and what does the change reach.

There is no database and no server. Everything Skein knows is in files you can read, review and merge like code.

```markdown
%rule[lex.comment syntax final] A line comment starts with `//` and ends with the line.
It is not a %[lex.token].
```

```text
$ skein check
skein: example: no problems (24 items of 2 types, 1 link types, 1 profiles, 31 citations)
```

## Getting it

Each [release](https://github.com/chasingdaylight/skein/releases) has `skein` as one program for Linux, macOS and Windows, with nothing else to install. For VS Code there is the extension `chasingdaylight.skein`, which highlights markers and references in Markdown and brings the `skein` program with it, on the `PATH` of its terminals.

## Where to start

Two tutorials, each a small project from nothing to a working setup, every command run as shown:

- [Skein in a project that has code](tutorial-existing-code.md): requirements written down for a program that exists, cited by its code and tests; what is tested, what a change reaches, a site of it.
- [Planning a project before the code](tutorial-planning.md): needs, requirements and the work that meets them, with people, a calendar, a schedule, a Gantt chart and a board.

## The documentation

These pages are of the release their menu names, the latest by default; the menu also lists the documentation of each earlier release, for a project that has not moved to the latest.

| Page | What it covers |
| --- | --- |
| [Writing items](writing-items.md) | Markers, parts, item files, references in text, citations in code and tests. |
| [Project files](project-files.md) | The `.skein/` directory: configuration, item types, link types, profiles. |
| [Commands](commands.md) | `check`, `trace`, `coverage`, `diff`, `impact`, `export`, `render`, `baseline`, `pin`, `examples`, `result`, `template`, `move`, `new`, `link`, `import`, `review`, `approve`, `lsp`. |
| [Reviewing](reviewing.md) | Fingerprints, suspect links, reviews and approvals. |
| [Other repositories](repositories.md) | Items of other repositories, `pin`, and the state of the network. |
| [Test results](results.md) | Reading test results, and what they say of each item. |
| [The forge](forge.md) | Issues and pull requests, checked against GitHub. |
| [Templates](templates.md) | Common ways of working, built into Skein: a project names one in one line. |
| [Importing](importing.md) | Bringing in Doorstop documents and CSV files. |
| [Design](design.md) | What Skein is for, how it is built, and what is planned. |
| [Requirements](requirements/readme.md) | What Skein is required to do, written in Skein and checked by Skein. |

The requirements pages are produced by `skein render` from the same files that `skein check` checks, so they show what a rendered project looks like.

## Status

Skein is early and its version is 0.x: the file formats can still change. The core, the command line, rendering, links across repositories, tested examples, test results, templates, planning, the forge adapters for GitHub and GitLab, the language server and the VS Code extension work and are tested on every platform. The [design](design.md) describes all of it, and what is still to come.
