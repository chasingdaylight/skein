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
skein shall carry a template for software work under NASA's NPR 7150.2D, `npr7150.2d`, as the NASA Software Engineering Handbook reads it: the NPR's requirements as a read-only source written into the project (each with its section, the classes that invoke it, the authority that tailors it, whether it binds only safety-critical software, and its handbook page), the handbook's reading of each, the types of the project's Requirements Mapping Matrix, tailoring with its approvals, software requirements, design, hazards, test procedures and non-conformances, and the document skeletons of the handbook's topics, with the handbook's expected maturity of each product at each milestone review (topic 7.08) and its software criteria for each review (topic 7.09) as read-only items. Its option `class` chooses the requirements the project must account for and the traces of SWE-052 it must keep; `safety-critical` adds the requirements of safety-critical software. The requirements were taken from NASA's pages once (by `tools/npr7150`) and are kept by hand from then on.

%req[templates.nasa-std-8739.8b]
skein shall carry a template for software assurance and software safety under NASA-STD-8739.8B, `nasa-std-8739.8b`, to be used with `npr7150.2d`: the standard's tasks for each requirement of the NPR (Table 1) and its requirements on the IV&V Provider (section 4.4.2) as a read-only source written into the project, the types of the assurance organization's mapping matrix, and skeletons of its documents. Its options `class` and `safety-critical` choose the groups of tasks a row of the matrix is expected for, as the NPR's do; `ivv` expects rows for the IV&V requirements.

%req[templates.nasa-std-7009b]
skein shall carry a template for models and simulations under NASA-STD-7009B, `nasa-std-7009b`: its 42 requirements as a read-only source written into the project, a type for each model with its intended use, its criticality (Appendix D) and its credibility factors (Appendix E), the rows of the Requirements Identification Matrix (Appendix A), and skeletons of the model register, the credibility assessments, the matrix, the plan and the results report.

%req[templates.nist-ai-rmf]
skein shall carry a template for AI risk management under the NIST AI RMF, `nist-ai-rmf`: the 72 subcategories of the core of NIST AI 100-1 (version 1.0, the latest published) and the twelve risks of the generative AI profile (NIST AI 600-1) as a read-only source written into the project, a type for each AI system with its purpose, kind, third-party supply and risk tier, the rows of the project's profile that say how each system addresses each subcategory, and skeletons of the AI inventory and the profile.

%req[templates.npr7150.2d-ai]
skein shall carry a template for AI in software projects under NPR 7150.2D, `npr7150.2d-ai`, to be used with `npr7150.2d`: what topics 7.25 (engineering) and 8.25 (assurance) of the NASA Software Engineering Handbook say bears on each requirement of the NPR, in skein's words, linked to the requirements, the six principles of NASA's framework for the ethical use of AI (NASA/TM-20210012886), and a skeleton of the assurance documents the handbook expects.

%req[templates.npr7123.1d]
skein shall carry a template for systems engineering under NASA's NPR 7123.1D, `npr7123.1d`: its 62 requirements and the entrance and success criteria of its 21 review tables (Appendix G) as a read-only source written into the project, the rows of its compliance matrix (Appendix H), the project's reviews with their kind and date, the checks of their criteria, and skeletons of the compliance matrix, the reviews and the systems engineering management plan.

%req[templates.npr7120.7a]
skein shall carry a template for IT program and project management under NASA's NPR 7120.7A (updated with Change 2), `npr7120.7a`: the 103 statements of the NPR that say "shall" (the preface and chapters 2 to 5) as a read-only source written into the project, each named by its paragraph and item and marked with whom it binds (IT service lines, IT projects, or both), with the documents the success criteria of each review list; the rows of the compliance matrix (Appendix C: comply, partially comply, not comply, not applicable), expected of the requirements of the kind of effort its option `kind` names; the project's reviews and key decision points with their dates, and the products filed for each; and skeletons of the matrix and the life cycle. The NPR's compliance matrices are images in the NPR and are not carried.

%req[templates.npr7120.5f]
skein shall carry a template for space flight program and project management under NASA's NPR 7120.5F, `npr7120.5f`: its 51 requirements as its compliance matrix (Table C-1) lists them, with their owners and who approves their tailoring, as a read-only source written into the project, the rows of the compliance matrix, the project's key decision points with their phases and dates, and skeletons of the matrix, the life cycle and the project plan.

%req[templates.iso29148]
skein shall carry a template for requirements as ISO/IEC/IEEE 29148:2018 describes them, `iso29148`: business, stakeholder, system and software requirements with the attributes the standard describes and its four verification methods, verifications, the links between the levels, and skeletons of its four specifications, a verification and traceability page, and a checklist of the characteristics of good requirements. The standard is under copyright: the template gives its structure in skein's own words, with its clause numbers, and quotes none of it.

%req[templates.eject]
`skein template eject NAME` shall write the types, links and profiles of a template the project uses into its `.skein/`, as the project's options make them, so that the project changes them freely; a file the project has already is left as it is. A template the project does not use is reported.
