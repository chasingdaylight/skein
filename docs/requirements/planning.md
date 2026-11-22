# Planning

Work as items: their planning attributes, the links that order them, and their schedule. The design is `docs/design.md`, section 10; the user documentation is in `docs/project-files.md`.

## Work items

%req[planning.roles]
An item type shall be work when it has a `[planning]` table, which names the attribute that holds each planning role: `start` and `finish` (dates), `duration`, `estimate`, `remaining` and `lag` (whole days, integers), `assignees`, `priority`, `milestone`, and `mode`. skein names no attribute itself. A role that names no attribute of the type, or one of another kind than the role takes, and a key that is no role, are problems of the schema. (emanspeaks, 2026-11-21, on #85.)

%req[planning.link-roles]
A link type shall take part in the schedule by its `[planning] role`: `precedes` (finish to start: the target starts once the item has finished, plus the target's lag), `parent` (the item is part of its target), or `blocks` (recorded, not scheduled). Any other role is a problem of the schema.

%req[planning.modes]
A work item shall be scheduled in one of two modes, the value of its `mode` attribute: `fixed`, which keeps the dates written for it, or `float`, which is scheduled from its predecessors and its parent. Without the attribute, an item with a start is fixed and one without is float.

%req[planning.checks]
`skein check` shall report, for work items: a value of the mode that is neither `fixed` nor `float`; a fixed item without a start; a finish before the start; a start, duration and finish that do not agree (the finish is the last of as many working days as the duration, from the start); a loop of predecessors or of parents; a work item that others follow and whose length is not known (no duration, nor a start and a finish); and a `precedes` or `parent` link to an item that is not work.

## Resources

%req[planning.resources]
skein shall hold people's capacities and calendars, compute their load, and report overallocation. (Design, section 10.2.)

%req[planning.people]
The people who do the work shall be listed in `.skein/resources.toml`, each under a handle the project chooses (`[people.ann]`), with a name, a capacity (a `share` of full-time work, or `hours` a week, not both), the days of the week they work when not the project's, and the days they are `absent` (dates, and `[first, last]` pairs). A work item's assignees are handles; one that is not listed is a problem `check` reports.

%req[planning.calendar]
The project's calendar shall be the `[calendar]` of the resources file: its working days of the week (`workdays`, default Monday to Friday), the `hours` of a working day (default 8), and its `holidays`. Durations count working days of it. A project without a calendar counts every day.

%req[planning.load]
`skein load` shall show each person's load week by week (ISO weeks): the effort of the work assigned to them, its estimate, else its duration, in days of the calendar's hours, spread evenly over the item's working days and shared evenly among its assignees, beside the hours they can work that week by their capacity, their working days, the holidays and their absences; with `--json`, as JSON. Work without dates is counted once it is scheduled.

%req[planning.overallocation]
`skein check` shall warn of each week in which a person has more work than hours to work, with both.
