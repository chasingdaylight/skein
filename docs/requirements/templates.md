# Templates

The user documentation is in `docs/templates.md`.

A template is a common way of working, built into skein: the item types, link types and profiles a kind of project needs, so that a project of that kind names it in one line rather than writing them in every repository.

%req[templates.builtin]
skein shall carry its templates in the program: each a directory of `templates/` in its repository, laid out as a project's `.skein/` is, with a `template.toml` that describes it and declares its options. Every file of `templates/` is built in, and nothing else; nothing is fetched.

%req[templates.use]
A project shall name the templates it uses in `.skein/config.toml`: `template = "NAME"`, `template = ["A", "B"]`, or `[template.KEY]` tables that give a template's `name` (else the key) and its options. The item types, link types and profiles of the templates are the project's, after `{{option}}` in their files is written as the option's value; the project's own file of a name in `.skein/types/`, `links/` or `profiles/` replaces a template's. A template skein does not have, an option a template does not declare, a value an option does not allow, an option without a default that is not given, and one name declared by two templates the project uses are reported.

%req[templates.commands]
`skein template list` shall name the templates, each with its description, and `skein template show NAME` give a template's description, its options (their values and defaults) and its files, by kind.
