# Planning

Work as items: their planning attributes, the links that order them, and their schedule. The design is `docs/design.md`, section 10; the user documentation is in `docs/project-files.md`.

## Work items

%req[planning.work-items]
Work shall be items with planning attributes (dates or durations, effort, assignees), linked to each other and to the product items they serve, scheduled from their dependencies, with the critical path computed. (Design, section 10.1.)

%req[planning.roles]
An item type shall be work when it has a `[planning]` table, which names the attribute that holds each planning role: `start` and `finish` (dates), `duration`, `estimate`, `remaining` and `lag` (whole days, integers), `assignees`, `priority`, `milestone`, and `mode`. skein names no attribute itself. A role that names no attribute of the type, or one of another kind than the role takes, and a key that is no role, are problems of the schema. (emanspeaks, 2026-11-21, on #85.)

%req[planning.link-roles]
A link type shall take part in the schedule by its `[planning] role`: `precedes` (finish to start: the target starts once the item has finished, plus the target's lag), `parent` (the item is part of its target), or `blocks` (recorded, not scheduled). Any other role is a problem of the schema.

%req[planning.modes]
A work item shall be scheduled in one of two modes, the value of its `mode` attribute: `fixed`, which keeps the dates written for it, or `float`, which is scheduled from its predecessors and its parent. Without the attribute, an item with a start is fixed and one without is float.

%req[planning.checks]
`skein check` shall report, for work items: a value of the mode that is neither `fixed` nor `float`; a fixed item without a start; a finish before the start; a start, duration and finish that do not agree (the finish is the last of as many working days as the duration, from the start); a loop of predecessors or of parents; a work item that others follow and whose length is not known (no duration, nor a start and a finish); and a `precedes` or `parent` link to an item that is not work.

## The schedule

%req[planning.schedule]
`skein schedule` shall schedule the work items. A fixed item keeps the dates written for it. A float item starts on the first working day after all its predecessors have finished, plus its lag in working days; with no predecessors, on the first working day of its parent, when the parent has dates of its own (fixed, or from its predecessors); and finishes after its duration in working days. A float parent with neither spans its children. A float item with nothing to schedule it from stays unscheduled, which `check` warns of. `skein schedule` writes `float` into each float item that names no mode, where its type has a mode, so that from then on every item gives its mode. (emanspeaks, 2026-11-21, on #85.)

%req[planning.critical-path]
The schedule shall give each scheduled item its slack, the working days it can finish later before an item after it or the end of the plan moves, and mark as critical the items without slack: the critical path.

%req[planning.stored]
`skein schedule` shall write the schedule to `.skein/schedule.toml`, a file the project commits and the one source of the schedule offline: every work item with its start, finish, mode, where its dates come from (`written`, `computed`, or `unscheduled`), its slack and whether it is critical. `[schedule] also = ["json", "csv"]` in the configuration writes `.skein/schedule.json` and `.skein/schedule.csv` beside it, from the same schedule, for tools that read those; skein reads only the TOML. (emanspeaks, 2026-11-21, on #85.)

%req[planning.schedule-checks]
`skein check` shall report a fixed item that starts before its predecessors let it, an item that runs outside its parent's dates (a parent that spans its children excepted), an item that finishes after its milestone (the work item its milestone names), and a stored schedule, in any of its formats, that is missing or not the one the work items give now.

## Time spent

%req[planning.time]
`skein time ITEM HOURS [--by NAME] [--on DATE] [--note TEXT]` shall log hours spent on a work item by a person on a day (by default git's user name and today), written to `.skein/time/` as one sorted line per item, person and day, in the file of the item's document, so that branches conflict only where they log the same day; hours logged for a day that already has some are added to them, rounded to hundredths. It refuses an item that is no work item or is in a read-only source, hours that are not more than 0, and a day that would have more than 24. `skein check` reports time of an item that is no work item and hours outside those bounds. (Design, section 10.1; emanspeaks, 2026-11-21.)

%req[planning.time-report]
`skein time` without arguments (also `--json`) shall set, for each work item that has an estimate or time spent, the estimate in hours (its estimate in days times the hours of the calendar's working day) against what was spent, the difference and who spent it, with the totals; and `time [TYPE...] [conditions]` in a document gives the same as a table.

## Issues on the forge

%req[planning.forge-fields]
A work item whose type has the planning role `issue` and whose `issue` attribute names an issue (`#12`, `owner/repo#12`) of the forge in `[forge]` shall take from the forge what the forge holds, as the adapter declares it; GitHub's are the issue's assignees, its milestone with the day it is due, and whether it is closed (not a start, a duration or effort, which stay in the item). An assignee or milestone the item does not write is the issue's; assignees the item writes that differ from the issue's are a warning of `skein check`; a closed issue is finished work (burndown, roadmap); and work with nothing else to place it, whose issue's milestone is due, finishes on that day and starts as many working days before as it lasts (source `forge` in the stored schedule). The forge is asked unless `--offline`; what it last said is kept and used when it cannot be reached, and the stored schedule is not compared while an issue cannot be learned. (Design, section 10.4; emanspeaks, 2026-11-21, on #85.)

## What-if plans

%req[planning.overlay]
A branch of the plan shall be able to deviate from what the forge holds without changing it: `skein overlay ISSUE FIELD VALUE` records, in `.skein/overlay.toml`, as one sorted line per issue and field, the fields where the plan differs (GitHub: `assignees`, `milestone`, `state`), each with the upstream value it was based on (what the forge says when it is made; `-` for no assignee or milestone), and `--remove` takes one out; `skein overlay` alone lists them. A value the forge says already is no deviation. The plan's views and schedule see the issue with the overlay applied, everything else still coming from the forge, and `skein check` reports a deviation whose upstream value has since changed (as a merge reports a conflict) and one of an issue no work item is. (Design, section 10.4; emanspeaks, 2026-11-21.)

%req[planning.apply]
`skein apply` shall write the overlay to the forge, through the adapter (GitHub: `gh`, signed in), and take what was written out of the overlay, deleting its file when it is empty. A field that changed on both sides, the forge's value now not being the one the deviation was based on, is not written and stays in the overlay, with the exit status of a problem, unless `--force`; one the forge already says is taken out; `--dry-run` says what would be written and writes nothing; a write the forge refuses leaves its deviations in the overlay, with its reason. It is not available with `--offline`.

## Progress

%req[planning.views]
skein shall draw Gantt charts, burndown and burnup charts, boards and a roadmap, as static pages: `render.gantt`, `render.burn`, `render.board` and `render.roadmap` in `docs/requirements/views.md`. (Design, section 10.3.)

%req[planning.burn]
skein shall count, for a milestone (the work item a work item's `milestone` role names) and each day of a span, the work in it (its scope) and the work done: in items, or in weight (an item's estimate, else its duration). Work is done when its status is one of `[planning] done` of its type, by default the type's last status before its tombstone. Each past day is the project as committed at the end of that day on the first-parent history of the checkout; today is the files as they are; so work added to or taken out of the milestone is a change of scope, and nothing is recorded by hand. (Design, section 10.3; emanspeaks, 2026-11-21.)

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
