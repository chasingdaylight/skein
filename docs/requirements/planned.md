# What is to come

What `docs/design.md` commits Skein to and the code does not do yet, in the order of the design's phases. These are coarse on purpose: each becomes requirements of its own, with tests, when its phase is built.

## Rendering and results

%req[render.site removed]

%req[baselines planned]
When a plan uses values the forge holds (dates, milestones), `skein baseline` shall first write them to a file under `.skein/baselines/`, commit it, and tag that commit. The tag itself is built. (Design, section 6; issue #298.)

## Editing

%req[edit.commands removed]

%req[edit.lsp removed]
