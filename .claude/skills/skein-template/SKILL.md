---
name: skein-template
description: Add or change one of skein's built-in templates (templates/NAME) - its manifest and options, types, links, profiles, configuration, project files, document skeletons, the file list, the test, the requirement and the docs. Use when building a template for a standard or way of working.
---

# Templates

A template is a directory of `templates/`, laid out as a project's `.skein/` is. Read `docs/templates.md` (the user's view) and `docs/requirements/templates.md` first; `templates/npr7150.2d` is the fullest example.

- `template.toml`: `description`, and `[options.NAME]` with `description`, `values`, `default` (none: the project must give it). `[options.NAME.sets.VALUE]` gives the values a choice sets besides (`trace_design = "true"`), which `{{trace_design}}` writes into the template's files, as `{{NAME}}` writes the option.
- `[[includes]]` in `template.toml`: the templates of the standards this one defers to, each `template = "NAME"`, `option`/`values` when only some values of an option bring it, and `because` (the requirement that defers to it, for `skein template show`). The one brought along takes the options of the same names. Trace the standard's own text for what it defers to (its applicable documents, and each requirement that names another document) before deciding.
- `types/`, `links/`, `profiles/`: as `.skein/` has them (`docs/project-files.md`). Attributes take no `description` key: say what they are in a comment.
- `config.toml`: what `skein init` adds to the project's configuration, such as citation sets (commented out when the places are the project's) and the read-only source of a standard.
- `project/standards/NAME/`: a standard's text as read-only items, which Skein provides to every project that names the template (written to `standards/NAME/` with a `.gitignore` that keeps it out of git, and read as a read-only source: `src/template/standards.zig`); the template's `config.toml` names no source for it. Its own text is NASA's or the standard's verbatim; it is left out of cspell (`templates/*/project/standards/**`).
- `documents/`: skeletons `skein init` writes under `docs/`, with document control front matter (`+++ document = "ID" revision = "Draft" +++`), references to the requirements they answer (`%[SWE-013]`), and generated pages (`list`, `matrix ... columns=`, `coverage`). An example item in a skeleton says it is one ("An example: replace it.").
- **The file list:** `bash tools/agent/register-templates.sh` rewrites `templates/__root__.zig`; a test holds it to the directory.
- **A test** in `src/template/_test/start.zig`: `init` with the template (several with `.templates = &.{ "a", "b" }`), the options given, `check` with no problems, the coverage it expects; cite its requirement.
- **A requirement** `templates.NAME` in `docs/requirements/templates.md`, and a row (and a section if it has options) in `docs/templates.md`.

Templates are only of NASA's and other US government standards, whose text may be included. A standard under copyright (ISO, IEEE) gets no template, not even in Skein's own words, for the IP risk (emanspeaks, 2026-11-27; #135, and `iso29148` removed). Always the latest revision of a standard (the trailing letter).
