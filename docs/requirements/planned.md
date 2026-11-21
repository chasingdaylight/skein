# What is to come

What `docs/design.md` commits skein to and the code does not do yet, in the order of the design's phases. These are coarse on purpose: each becomes requirements of its own, with tests, when its phase is built.

## Rendering and results

%req[render.site planned]
`skein render` shall build a static site from the project: its documents with every item anchored by its ID, references as links, each item's "referenced by", and generated matrices, coverage pages and filtered lists. (Design, section 8.)

%req[render.documents planned]
Each document shall also be rendered as one self-contained file with a print style sheet, for delivery as a document. (Design, section 8.)

%req[render.profiles planned]
A document or the site shall be renderable for one profile. (Design, section 8.)

%req[results.import planned]
skein shall import test results (JUnit XML, TAP, and a format of its own), record which implementation and version produced them, and attach them to the items the tests cite. (Design, section 4.5.)

%req[verification.records planned]
An item whose verification method is not a test shall be verified by a record of that verification, with its evidence; coverage shall count an item as verified by whichever its method requires. (Design, section 4.5.)

%req[standards.external planned]
A standard the project must comply with shall be an item set of its own, read-only, which the project's items link to, with applicability by profile and with waivers and deviations as item types. (Design, section 4.7.)

%req[baselines planned]
`skein baseline` shall freeze a named state of the project as a git tag, first writing what a tag alone would not hold. (Design, section 6.)

%req[forge.adapter planned]
An adapter per forge shall resolve references to issues and pull requests, report `check` and `coverage` in the forge's CI, and record the approvals of a merged change. (Design, section 7.)

%req[links.repositories planned]
Items, code and tests of another repository shall be citable by a qualified reference, checked against a recorded commit of that repository. (Design, section 10.5.)

## Planning

%req[planning.work-items planned]
Work shall be items with planning attributes (dates or durations, effort, assignees), linked to each other and to the product items they serve, scheduled from their dependencies, with the critical path computed. (Design, section 10.1.)

%req[planning.views planned]
skein shall draw Gantt charts, burndown and burnup charts, boards and a roadmap, as static pages. (Design, section 10.3.)

%req[planning.resources planned]
skein shall hold people's capacities and calendars, compute their load, and report overallocation. (Design, section 10.2.)

%req[planning.forge planned]
What a forge holds about an issue shall stay there and be read through the adapter; `.skein/` holds only what the forge lacks. A what-if plan is a branch whose deviations from the forge are kept as an overlay, and a full mirror is an option. (Design, section 10.4.)

## Editing

%req[edit.commands planned]
`skein new`, `move` and `link` shall create items with the next free ID, rename IDs everywhere they are used, and add links. (Design, section 5.)

%req[edit.lsp planned]
`skein lsp` shall be a language server for the item and document sources: go to definition, find references, completion of IDs, hover, diagnostics from `check`, and rename. (Design, section 9.)

%req[edit.vscode planned]
A VS Code extension on the language server shall be skein's graphical interface, with the item tree, trace and coverage views, forms for items, and interactive planning views. (Design, section 9.)
