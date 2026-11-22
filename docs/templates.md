# Templates

A template is a way of working that comes with skein: the item types, link types and profiles a kind of project needs. A project of that kind names it in one line rather than writing them out in every repository:

```toml
# .skein/config.toml
template = "langspec"

[[sources]]
path = "spec"
```

The project then has the template's types and links as if they were in its `.skein/`. A file of its own of the same name, `.skein/types/rule.toml` say, replaces the template's: so a project takes what fits and changes the rest.

```text
$ skein template list
langspec  The specification of a programming language: rules, terms, and examples that show them

$ skein template show langspec
```

## Starting from a template, and changing it

`skein init --template langspec` starts a project in the current directory (or `--root DIR`): `.skein/config.toml` that uses the template, with its options at their defaults, and the template's document skeletons under `docs/`, ready for `skein check`. Without `--template`, `skein init` writes the configuration alone.

`skein template eject langspec` writes the template's types, links and profiles into `.skein/`, as the project's options make them. They become the project's own files and replace the template's, to be changed as the project likes; a file the project has already is left as it is.

## Several templates, and options

A project can use several, for what it is at once: `template = ["langspec", "npr7150.2d"]`. Two templates that declare the same name are reported, until the project declares that name itself.

A template can take options, which choose among what it declares: a software class, whether software is safety-critical. They are given in a table per template:

```toml
[template.npr]
name = "npr7150.2d"
class = "C"
safety-critical = false
```

`skein template show NAME` lists a template's options, their values and their defaults. An option the template does not have, or a value it does not allow, is reported.

## The templates

| Template | For |
| --- | --- |
| `langspec` | The specification of a programming language: rules (syntax, legality, static and dynamic semantics), terms, examples that show the rules (tested examples, expected of every rule), and conformance tests, kept as items (`test`, linked by `verifies`) or cited from the test code. `skein init` writes a charter, a first chapter, a glossary and a coverage page, and a citation set for the tests to fill in. Profiles for the stages or editions of the language are the project's own. |

| `npr7150.2d` | Software work under NASA's NPR 7150.2D, NASA Software Engineering Requirements, as the NASA Software Engineering Handbook (NASA-HDBK-2203) reads it. See below. |

More are planned: requirements as ISO/IEC/IEEE 29148 describes them, NASA-STD-8739.8B (software assurance and safety) and NASA-STD-7009B (models and simulations), the last two to go with `npr7150.2d`.

## NPR 7150.2D

```toml
[template.npr]
name = "npr7150.2d"
class = "C"                 # A to F (Appendix D); required
safety-critical = false     # whether the project has safety-critical software (SWE-205)
```

`skein init --template npr7150.2d` writes, besides the configuration:

- `standards/npr7150.2d/`, read-only: the NPR's chapters 2 to 5, each requirement an item (`SWE-013`, its lettered sub-parts its parts, `SWE-134.a`) with its section, the classes that invoke it and the authority that tailors it (Appendix C), and its page in the handbook; and `guidance.md`, the handbook's reading of each (`HB-013`): what complying means in practice, the objective evidence, the documents that hold it, the milestones, the small-project advice and what software assurance does. They are written by `tools/npr7150` in skein's repository from NASA's pages, and are not edited.
- `docs/`: the Requirements Mapping Matrix, the classification record, and a skeleton of each document of the handbook's topics 5.01 to 5.24 (development plan, configuration management, assurance, requirements, design, data dictionary, test plan, procedures and report, version description, maintenance plan, user manual, metrics, peer reviews, problem reports, hazards, traceability, risks, estimates), with document control.

The project's records are items of the template's types: `compliance` (a row of the matrix: FC, T, PC, NC or NA, linked by `complies` to a requirement, per component if need be), `tailoring` (a deviation or waiver, linked by `tailors`, in force once the Technical Authorities approve it), `requirement` (`SRS-001`), `system`, `hazard`, `design`, `procedure` and `nonconformance`. The option `class` makes `skein coverage` expect a row of the matrix for each requirement the class invokes (the profile `class`), and the traces of SWE-052 the class requires: higher-level requirements, hazards, design, verifications and non-conformances. `safety-critical = true` adds the requirements of safety-critical software (SWE-023, SWE-134, SWE-219, SWE-220).

## Writing one

A template is a directory of `templates/` in skein's repository, laid out as `.skein/` is (`types/`, `links/`, `profiles/`), with `documents/` for the skeletons `skein init` writes under `docs/`, an optional `config.toml` that `skein init` adds to the project's configuration (citation sets, say, which a template cannot declare), `project/` for files `skein init` writes where they stand (a standard's read-only text), and a `template.toml`:

```toml
description = "What it is for, in one line"

[options.class]
description = "The software class of the project"
values = ["A", "B", "C", "D", "E", "F"]
default = "C"
```

In its files, `{{class}}` is written as the value of the option. A value can set others, for what differs by class:

```toml
[options.class.sets.A]
trace_design = "true"

[options.class.sets.D]
trace_design = "false"
```

and a link type then says `expected = {{trace_design}}`. Every file of `templates/` is listed in `templates/__root__.zig`, which builds them into skein; a test holds the list to the directory.
