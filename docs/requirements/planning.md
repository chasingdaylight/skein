# Planning

Work as items: their planning attributes, the links that order them, and their schedule. The design is `docs/design.md`, section 10; the user documentation is in `docs/project-files.md`.

## Work items

%req[planning.roles]
An item type shall be work when it has a `[planning]` table, which names the attribute that holds each planning role: `start` and `finish` (dates), `duration`, `estimate`, `remaining` and `lag` (whole days, integers), `assignees`, `priority`, `milestone`, and `mode`. skein names no attribute itself. A role that names no attribute of the type, or one of another kind than the role takes, and a key that is no role, are problems of the schema. (emanspeaks, 2026-11-21, on #85.)

%req[planning.link-roles]
A link type shall take part in the schedule by its `[planning] role`: `precedes` (finish to start: the target starts once the item has finished, plus the target's lag), `parent` (the item is part of its target), or `blocks` (recorded, not scheduled). Any other role is a problem of the schema.

%req[planning.modes]
A work item shall be scheduled in one of two modes, the value of its `mode` attribute: `fixed`, which keeps the dates written for it, or `float`, which is scheduled from its predecessors and its parent. Without the attribute, an item with a start is fixed and one without is float. A day is a calendar day until calendars come with resources.

%req[planning.checks]
`skein check` shall report, for work items: a value of the mode that is neither `fixed` nor `float`; a fixed item without a start; a finish before the start; a start, duration and finish that do not agree (the finish is the start plus the duration less one day); a loop of predecessors or of parents; a work item that others follow and whose length is not known (no duration, nor a start and a finish); and a `precedes` or `parent` link to an item that is not work.
