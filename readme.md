# skein

Plain-text requirements, specifications and traceability, kept in git.

skein holds the threads of a project together: what is needed, what is decided, what is specified, how it is built, and what proves it. Every item is a piece of Markdown in the repository with a stable ID, a type and typed links. skein checks the whole graph, traces it in both directions, flags what a change makes suspect, imports test results, plans the work (schedules, resources, Gantt charts, burndown), and generates the views a team reads: specifications, matrices, coverage, plans and reports.

It is for projects that want the rigor of requirements management without a database or a proprietary tool: from a language specification written as atomic, numbered paragraphs (like the Ferrocene Language Specification) to a NASA-style V-model of system requirements, software requirements, design and tests.

**Status:** design. `docs/design.md` describes what skein is to be; no code yet.

## Principles

- **Plain text in git is the source of truth.** Reviewable in pull requests, versioned with the code, readable by people and agents.
- **Forge-neutral.** Works with nothing but a git repository; GitHub, GitLab and Forgejo integrations are adapters on top.
- **Schema-driven.** Each project declares its item types, links and rules; skein enforces them.
- **Prose-friendly.** An item can be its own file or a paragraph inside a document, so specifications read as documents.
- **One binary, one codebase.** Written in Zig, with no runtime dependencies and nothing fetched at build time, so it can be used where outside dependencies need approval.

## License

MIT, see `LICENSE`.
