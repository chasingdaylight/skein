# skein

![The skein logo: a skein of red yarn on a pin board](docs/assets/logo.svg)

Plain-text requirements, specifications and traceability, kept in git.

skein holds the threads of a project together: what is needed, what is decided, what is specified, how it is built, and what proves it. Every item is a piece of Markdown in the repository with a stable ID, a type and typed links. skein checks the whole graph, traces it in both directions, flags what a change makes suspect, imports test results, plans the work (schedules, resources, Gantt charts, burndown), and generates the views a team reads: specifications, matrices, coverage, plans and reports.

It is for projects that want the rigor of requirements management without a database or a proprietary tool: from a language specification written as atomic, numbered paragraphs (like the Ferrocene Language Specification) to a NASA-style V-model of system requirements, software requirements, design and tests.

**Status:** early. The core and the command line work: a project's schema, items in documents and in files of their own, citations in code and tests, and the commands `check`, `trace`, `coverage`, `diff`, `impact`, `review`, `clear`, `approve`, `export`, `import`, `render` (a static site, or Markdown for a site generator) `move` (renaming an ID everywhere), `new` (starting an item with the next free ID), `link` (adding a link), `baseline` (tagging a state of the project) and `lsp` (a language server: problems, go to definition, references, hover, completion and rename in any editor). Rendering HTML sites and documents by itself, test results, planning and the editor support are to come; `docs/design.md` describes all of it.

## Installing

Each [release](https://github.com/chasingdaylight/skein/releases) has `skein` as one program for Linux, macOS and Windows (x86_64 and arm64), with a `SHA256SUMS` file. Unpack the archive for your platform and put `bin/skein` on your `PATH`; it needs nothing else.

For VS Code and editors built on it, the extension [skein](editors/vscode/readme.md) (`chasingdaylight.skein`, on the Visual Studio Marketplace and Open VSX) highlights markers and references in Markdown and carries the `skein` program for its platform, on the `PATH` of its terminals.

## Trying it

Or build with Zig 0.17.1 (`zig build`; the binary is `zig-out/bin/skein`). Then in one of the examples:

```text
cd examples/requirements
skein check
skein trace SYS-001
skein coverage
```

| Read | For |
| --- | --- |
| [`examples/`](examples/) | Two small projects to copy from: a specification as a document, and requirements as files. |
| [`docs/writing-items.md`](docs/writing-items.md) | How items, references and citations are written. |
| [`docs/project-files.md`](docs/project-files.md) | The files in `.skein/`: item types, link types, profiles. |
| [`docs/commands.md`](docs/commands.md) | The commands. |
| [`docs/reviewing.md`](docs/reviewing.md) | Fingerprints, suspect links, approvals. |
| [`docs/repositories.md`](docs/repositories.md) | Referring to the items of other repositories. |
| [`docs/results.md`](docs/results.md) | Test results. |
| [`docs/importing.md`](docs/importing.md) | Coming from Doorstop, or from a spreadsheet. |
| [`docs/requirements/`](docs/requirements/readme.md) | What skein is required to do, in its own format, traced to its tests. |
| [`docs/design.md`](docs/design.md) | What skein is to be. |

## Principles

- **Plain text in git is the source of truth.** Reviewable in pull requests, versioned with the code, readable by people and agents.
- **Forge-neutral.** Works with nothing but a git repository; GitHub, GitLab and Forgejo integrations are adapters on top.
- **Schema-driven.** Each project declares its item types, links and rules; skein enforces them.
- **Prose-friendly.** An item can be its own file or a paragraph inside a document, so specifications read as documents.
- **One binary, one codebase.** Written in Zig, with no runtime dependencies and nothing fetched at build time, so it can be used where outside dependencies need approval.

## License

MIT, see `LICENSE`.
