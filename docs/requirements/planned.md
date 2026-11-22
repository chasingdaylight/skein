# What is to come

What `docs/design.md` commits skein to and the code does not do yet, in the order of the design's phases. These are coarse on purpose: each becomes requirements of its own, with tests, when its phase is built.

## Rendering and results

%req[render.site removed]

%req[standards.external]
A standard the project must comply with shall be an item set of its own, read-only, which the project's items link to, with applicability by profile and with waivers and deviations as item types. (Design, section 4.7.) Built: `standards.read-only`, `standards.waivers`, profiles, and generated matrices.

%req[baselines planned]
When a plan uses values the forge holds (dates, milestones), `skein baseline` shall first write them to a file under `.skein/baselines/`, commit it, and tag that commit. The tag itself is built. (Design, section 6.)

%req[forge.adapter planned]
An adapter per forge shall resolve references to issues and pull requests, report `check` and `coverage` in the forge's CI, and record the approvals of a merged change. (Design, section 7.) GitHub's is built (`docs/requirements/forge.md`); GitLab's and Forgejo's are to come.

%req[links.repositories]
Items, code and tests of another repository shall be citable by a qualified reference, checked against a recorded commit of that repository. (Design, section 10.5.)

## Planning

%req[planning.views planned]
skein shall draw Gantt charts, burndown and burnup charts, boards and a roadmap, as static pages. (Design, section 10.3.) Built: Gantt charts (`render.gantt`).

%req[planning.forge planned]
What a forge holds about an issue shall stay there and be read through the adapter; `.skein/` holds only what the forge lacks. A what-if plan is a branch whose deviations from the forge are kept as an overlay, and a full mirror is an option. (Design, section 10.4.)

## Editing

%req[edit.commands removed]

%req[edit.lsp removed]

%req[edit.vscode planned]
A VS Code extension on the language server shall be skein's graphical interface, with the item tree, trace and coverage views, forms for items, and interactive planning views. (Design, section 9.) Built: the tree, the views, code lenses and quick fixes (`vscode.*` in `docs/requirements/editing.md`); forms and planning views are to come.
