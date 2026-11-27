# Templates

A template is a way of working that comes with Skein: the item types, link types and profiles a kind of project needs. A project of that kind names it in one line rather than writing them out in every repository:

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

`skein init --template langspec` starts a project in the current directory (or `--root DIR`): `.skein/config.toml` that uses the template, with its options at their defaults, and the template's document skeletons under `docs/`, ready for `skein check`. `--template` may be given more than once, for a template and the overlays that go with it. `--option NAME=VALUE`, also given more than once, gives a template's option in place of its default, so the configuration is complete from the start and the templates the options bring along have their documents written too: `skein init --template npr7150.2d --option class=C`. Without `--template`, `skein init` writes the configuration alone.

A template that carries a standard (NPR 7150.2D, NASA-STD-8739.8B and the others below) gives its text as read-only items from Skein itself: it is written to `standards/NAME/` with a `.gitignore` there, so it is never committed, and written again when a newer Skein corrects it. The repository holds only what the project writes. A project started before this, with the standard copied in and named in a `[[sources]]` of its own, keeps its copy; `skein check` says when the copy is the template's text unchanged, so that the directory and its `[[sources]]` can go.

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
| `nasa-std-8739.8b` | Software assurance and software safety under NASA-STD-8739.8B, with `npr7150.2d`: the standard's tasks for each requirement of the NPR and its IV&V requirements, read-only, and the assurance organization's mapping matrix. See below. |
| `nasa-std-7009b` | Models and simulations under NASA-STD-7009B: its 42 requirements (`MS-40` for `[M&S 40]`), read-only; each model (`MDL-001`) with its intended use, its criticality (consequence I to V, influence 1 to 5, red, yellow or green) and its eleven credibility factors at levels 0 to 4; the rows of the Requirements Identification Matrix (`ms-record`, linked by `meets`, with the model); skeletons of the register, the credibility tables, the matrix, the plan and the results report. With `npr7150.2d` or alone. |
| `nist-ai-rmf` | AI risk management under the NIST AI RMF (NIST AI 100-1, version 1.0): its 72 subcategories (`govern.1.1` for GOVERN 1.1) and the twelve risks of the generative AI profile (NIST AI 600-1, `gen-ai.confabulation`), read-only; each AI system (`AIS-001`, with purpose, kind, third-party supply and risk tier, linked by `exposed-to` to the risks it faces); the rows of the profile (`ai-rmf-record`, linked by `ai-rmf-addresses`, with the system); skeletons of the inventory and the profile. |
| `npr7150.2d-ai` | AI in a software project under NPR 7150.2D, with `npr7150.2d`: what handbook topics 7.25 and 8.25 say bears on each requirement (`AIN-003`, linked by `bears-on` to `SWE-219`), in Skein's words, and the six principles of NASA's framework for the ethical use of AI (`ethic.fair`), read-only; a skeleton of the assurance documents the handbook expects. With `nist-ai-rmf`, whose subcategories the notes complement. |
| `npr7123.1d` | Systems engineering under NPR 7123.1D: its 62 requirements (`SE-07`) with their rationale, and the entrance and success criteria of its 21 review tables (`G-6`, the PDR's, with `G-6.e1` and `G-6.s1`), read-only; the compliance matrix (`se-compliance`, FC, T or NA, linked by `complies-se`), the project's reviews (`REV-001`, with kind and date, `judged-by` a table) and the checks of their criteria (`review-check`, `fulfills`); skeletons of the matrix, the reviews and the systems engineering management plan. With `npr7150.2d` or alone. |
| `npr7120.7a` | IT program and project management under NPR 7120.7A (Change 2): its 105 "shall" statements (`IT-3.3.a`, with the scope `service-line`, `project` or `both`), read-only, each with the documents of its review's success criteria; the NPR's own compliance matrix (Appendix C, Tables C-1 to C-9) as 155 read-only rows (`ITA-C5.14`: the action, the product state it is due in, the paragraphs it answers, the review), from which Appendix D's gate product grids follow; the project's rows of it (`it-compliance`, `complies-it`: C, PC, NC, NA), expected of the NPR's rows for the option `kind` (`project`, the default, or `service-line`); the reviews and key decision points (`ITR-001`, with kind and date) and the products filed for each (`ITP-001`, `filed-for`); skeletons of the matrix and the life cycle. With `npr7150.2d` for the software of the IT project. |
| `npr7120.5f` | Space flight program and project management under NPR 7120.5F (with NID 7120.148): its 51 requirements as Table C-1 lists them (`PM-2.2.5`, with owner, delegation and the approvers of tailoring), read-only; the compliance matrix (`pm-compliance`, `complies-pm`); the key decision points (`KDP-B`, with phase and date); skeletons of the matrix, the life cycle and the project plan. With `npr7123.1d`, whose reviews fall between its key decision points. |
| `human-rating` | Human-rating of crewed space systems: NPR 8705.2C's certification requirements (`HRC-2.2.1`, with their titles, and when the certification package holds each: `srr=I pdr=U`, Appendix D) and the roles of its section 1.4, and NASA-STD-8719.29's technical requirements (`HR-4.3.1`), each with its notes and rationale, read-only; the compliance matrix (`hr-compliance`, FC, T or NA, linked by `complies-hr`); skeletons of the matrix and of the Human-Rating Certification Package. With `npr7150.2d` for the software of a crewed system (class A) or alone. |

More are planned: the software products' maturity at each review, to go with `npr7150.2d`.

## NPR 7150.2D

```toml
[template.npr]
name = "npr7150.2d"
class = "C"                 # A to F (Appendix D); required
safety-critical = false     # whether the project has safety-critical software (SWE-205)
program = "none"            # space-flight (NPR 7120.5), it (NPR 7120.7) or none
models-and-simulations = false  # models, simulations or tools qualify flight software (SWE-070)
crewed = false              # part of a crewed system to be human-rated (NPR 8705.2)
```

NPR 7150.2D defers to other standards, whose products a project under it delivers too, so the template brings their templates along, with the same options (`skein template show npr7150.2d` lists them):

| Brings | When | Because |
| --- | --- | --- |
| `nasa-std-8739.8b` | class A to E | SWE-022 (software assurance, software safety and IV&V per NASA-STD-8739.8) and SWE-205 (the safety-critical software determination) |
| `nasa-std-7009b` | `models-and-simulations = true` | SWE-070 and SWE-073, as the handbook reads them |
| `npr7120.5f`, `npr7123.1d` | `program = "space-flight"` | P.4, SWE-126, SWE-141, SWE-143, SWE-153, SWE-218; NPR 7123.1 for the systems engineering |
| `npr7120.7a` | `program = "it"` | P.4, SWE-126 |
| `human-rating` | `crewed = true` | P.4: NPR 8705.2 |

So a project of class A to E always has the safety-critical software determination (`docs/safety-criticality.md`, of NASA-STD-8739.8B's template), which says, when the software is not safety-critical, that it was found not to be and why. A template brought along by an option given to `skein init` (`--option class=C`) has its documents written with the others; one brought along by an option given later has them written by `skein template documents`; `skein check` says when one has none yet.

`skein init --template npr7150.2d` writes, besides the configuration:

- `standards/npr7150.2d/`, read-only: the NPR's chapters 2 to 5, each requirement an item (`SWE-013`, its lettered sub-parts its parts, `SWE-134.a`) with its section, the classes that invoke it and the authority that tailors it (Appendix C), and its page in the handbook; and `guidance.md`, the handbook's reading of each (`HB-013`): what complying means in practice, the objective evidence, the documents that hold it, the milestones, the small-project advice and what software assurance does. They were taken from NASA's pages on 2026-11-22 (by `tools/npr7150` in Skein's repository) and are kept by hand from there, when NASA revises the NPR; a project does not edit them (they are a read-only source).
- `docs/`: the Requirements Mapping Matrix, the classification record, and a skeleton of each document of the handbook's topics 5.01 to 5.24 (development plan, configuration management, assurance, requirements, design, data dictionary, test plan, procedures and report, version description, maintenance plan, user manual, metrics, peer reviews, problem reports, hazards, traceability, risks, estimates), with document control.

The project's records are items of the template's types: `compliance` (a row of the matrix: FC, T, PC, NC or NA, linked by `complies` to a requirement, per component if need be), `tailoring` (a deviation or waiver, linked by `tailors`, in force once the Technical Authorities approve it), `requirement` (`SRS-001`), `system`, `hazard`, `design`, `procedure` and `nonconformance`. The option `class` makes `skein coverage` expect a row of the matrix for each requirement the class invokes (the profile `class`), and the traces of SWE-052 the class requires: higher-level requirements, hazards, design, verifications and non-conformances. `safety-critical = true` adds the requirements of safety-critical software (SWE-023, SWE-134, SWE-219, SWE-220).

## NASA-STD-8739.8B

An overlay on `npr7150.2d`, for the software assurance organization's side of the same project:

```sh
skein init --template npr7150.2d --template nasa-std-8739.8b
```

```toml
[template."nasa-std-8739.8b"]
class = "C"                 # as for npr7150.2d
safety-critical = false
ivv = false                 # whether IV&V is performed on the project (SWE-141)
```

It writes `standards/nasa-std-8739.8b/`, read-only: Table 1 of the standard, the tasks of each requirement of the NPR as an item (`SA-013`, assuring SWE-013) with each task a part (`SA-013.1`), with the requirement's classes; SASS-01; and the 49 requirements of section 4.4.2 on the IV&V Provider (`IVV-001` for 4.4.2.1). The assurance organization's mapping matrix (handbook topic 8.51) is items of the type `assurance` (FC, T, PC, NC or NA), linked by `performs` to the tasks they cover, expected for the task groups of every requirement the class invokes, and by `ivv-performs` to the IV&V requirements when `ivv` is true. `docs/` gets the matrix, the safety plan, the assurance status report, the analyses and the IV&V project execution plan.

The standard's text was taken from its PDF on 2026-11-22 (with Skein's `tools/pdf`) and is kept by hand from there.

## Writing one

A template is a directory of `templates/` in Skein's repository, laid out as `.skein/` is (`types/`, `links/`, `profiles/`), with `documents/` for the skeletons `skein init` writes under `docs/`, an optional `config.toml` that `skein init` adds to the project's configuration (citation sets, say, which a template cannot declare), `project/standards/NAME/` for a standard's read-only text, which Skein provides to every project that uses the template (see above), and a `template.toml`:

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

and a link type then says `expected = {{trace_design}}`. Every file of `templates/` is listed in `templates/__root__.zig`, which builds them into Skein; a test holds the list to the directory.
