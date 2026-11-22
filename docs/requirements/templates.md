# Templates

The user documentation is in `docs/templates.md`.

A template is a common way of working, built into skein: the item types, link types and profiles a kind of project needs, so that a project of that kind names it in one line rather than writing them in every repository.

%req[templates.builtin]
skein shall carry its templates in the program: each a directory of `templates/` in its repository, laid out as a project's `.skein/` is, with a `template.toml` that describes it and declares its options. Every file of `templates/` is built in, and nothing else; nothing is fetched.

%req[templates.use]
A project shall name the templates it uses in `.skein/config.toml`: `template = "NAME"`, `template = ["A", "B"]`, or `[template.KEY]` tables that give a template's `name` (else the key) and its options. The item types, link types and profiles of the templates are the project's, after `{{option}}` in their files is written as the option's value; the project's own file of a name in `.skein/types/`, `links/` or `profiles/` replaces a template's. A template skein does not have, an option a template does not declare, a value an option does not allow, an option without a default that is not given, and one name declared by two templates the project uses are reported.

%req[templates.commands]
`skein template list` shall name the templates, each with its description, and `skein template show NAME` give a template's description, its options (their values and defaults) and its files, by kind.

%req[templates.init]
`skein init` shall start a project in a directory that has none: `.skein/config.toml` with a source of documents in `docs/`. With `--template NAME` the configuration uses the template, with each of its options at its default (an option without one is written as a comment, to be given), and the template's document skeletons (its `documents/`) are written under `docs/`, their options filled in. A template skein does not have, and a directory that has a project already, are reported and nothing is written.

%req[templates.eject]
`skein template eject NAME` shall write the types, links and profiles of a template the project uses into its `.skein/`, as the project's options make them, so that the project changes them freely; a file the project has already is left as it is. A template the project does not use is reported.
