# Templates

The user documentation is in `docs/templates.md`.

A template is a common way of working, built into skein: the item types, link types and profiles a kind of project needs, so that a project of that kind names it in one line rather than writing them in every repository.

%req[templates.builtin]
skein shall carry its templates in the program: each a directory of `templates/` in its repository, laid out as a project's `.skein/` is, with a `template.toml` that describes it and declares its options. Every file of `templates/` is built in, and nothing else; nothing is fetched.

%req[templates.use]
A project shall name the templates it uses in `.skein/config.toml`: `template = "NAME"`, `template = ["A", "B"]`, or `[template.KEY]` tables that give a template's `name` (else the key) and its options. The item types, link types and profiles of the templates are the project's, after `{{option}}` in their files is written as the option's value, and `{{name}}` as a value an option's value sets (`[options.class.sets.A]`); the project's own file of a name in `.skein/types/`, `links/` or `profiles/` replaces a template's. A template skein does not have, an option a template does not declare, a value an option does not allow, an option without a default that is not given, and one name declared by two templates the project uses are reported.

%req[templates.commands]
`skein template list` shall name the templates, each with its description, and `skein template show NAME` give a template's description, its options (their values and defaults) and its files, by kind.

%req[templates.init]
`skein init` shall start a project in a directory that has none: `.skein/config.toml` with a source of documents in `docs/`. With `--template NAME`, given once or more, the configuration uses the templates, each with each of its options at its default (an option without one is written as a comment, to be given), followed by the template's `config.toml` when it has one, the template's `project/` files where they say (a standard's read-only text), and the template's document skeletons (its `documents/`) are written under `docs/`, their options filled in. A template skein does not have, and a directory that has a project already, are reported and nothing is written.

%req[templates.npr]
skein shall carry a template for software work under NASA's NPR 7150.2D, `npr7150.2d`, as the NASA Software Engineering Handbook reads it: the NPR's requirements as a read-only source written into the project (each with its section, the classes that invoke it, the authority that tailors it, whether it binds only safety-critical software, and its handbook page), the handbook's reading of each, the types of the project's Requirements Mapping Matrix, tailoring with its approvals, software requirements, design, hazards, test procedures and non-conformances, and the document skeletons of the handbook's topics. Its option `class` chooses the requirements the project must account for and the traces of SWE-052 it must keep; `safety-critical` adds the requirements of safety-critical software. The requirements are written by a program in `tools/npr7150` from NASA's pages, never by hand.

%req[templates.nasa-std-8739.8b]
skein shall carry a template for software assurance and software safety under NASA-STD-8739.8B, `nasa-std-8739.8b`, to be used with `npr7150.2d`: the standard's tasks for each requirement of the NPR (Table 1) and its requirements on the IV&V Provider (section 4.4.2) as a read-only source written into the project, the types of the assurance organization's mapping matrix, and skeletons of its documents. Its options `class` and `safety-critical` choose the groups of tasks a row of the matrix is expected for, as the NPR's do; `ivv` expects rows for the IV&V requirements.

%req[templates.nasa-std-7009b]
skein shall carry a template for models and simulations under NASA-STD-7009B, `nasa-std-7009b`: its 42 requirements as a read-only source written into the project, a type for each model with its intended use, its criticality (Appendix D) and its credibility factors (Appendix E), the rows of the Requirements Identification Matrix (Appendix A), and skeletons of the model register, the credibility assessments, the matrix, the plan and the results report.

%req[templates.iso29148]
skein shall carry a template for requirements as ISO/IEC/IEEE 29148:2018 describes them, `iso29148`: business, stakeholder, system and software requirements with the attributes the standard describes and its four verification methods, verifications, the links between the levels, and skeletons of its four specifications, a verification and traceability page, and a checklist of the characteristics of good requirements. The standard is under copyright: the template gives its structure in skein's own words, with its clause numbers, and quotes none of it.

%req[templates.eject]
`skein template eject NAME` shall write the types, links and profiles of a template the project uses into its `.skein/`, as the project's options make them, so that the project changes them freely; a file the project has already is left as it is. A template the project does not use is reported.
