# Test results

The user documentation is in `docs/results.md`.

Test results say whether what the items require holds: a CI run's, given to one command, or a record the project keeps, as a project that files test reports must.

%req[results.import]
Skein shall read test results in a format of its own, record which implementation and version produced each, and attach them to the items they are about. JUnit XML and TAP are for later (#129).

%req[results.formats]
A results file shall be TOML, JSON or YAML, told apart by its extension (`.toml`, `.json`, `.yaml`, `.yml`), each a list of results with the same fields: `test` (its name), `file` (of the test, from the project's root), `item`, `items`, `result` (`pass`, `fail` or `skip`), `implementation`, `version` and `note`. In TOML the list is `[[result]]` tables; in JSON an array, or an object with a `result` array; in YAML a list, or a `result:` list. A file that cannot be read, a result without `result`, and a `result` other than the three are reported.

%req[results.kept]
The results files a project keeps shall be read from the files and directories `[results] paths` names, by every command that uses results; `trace` and `coverage` also take `--results FILE`, more than once, for a run's results that are not kept.

%req[results.mapping]
A result shall belong to the items cited in the file of its test (`file`), to the item it names (`item`), a procedure run by a person, say, and to the items that item links to, and to the items it names (`items`). A former ID names the item it was.

%req[results.verdicts]
Per implementation, an item shall pass when every result that belongs to it passed, fail when one failed, and be untested when none belongs to it or all were skipped; results of several implementations are never merged. `coverage` gives, per implementation, how many of the items passed, which failed and which are untested, counting the items of the types a citation set expects to be cited and the items that have results; `trace` gives an item's verdict and its results per implementation.

%req[results.recorded]
`skein result ID pass|fail|skip [--note TEXT] [--by NAME] [--on DATE] [--implementation NAME]` shall record a result a person obtained, such as a procedure of a test plan carried out by hand, in the results the project keeps: in the first of `[results] paths`, a TOML file, or `recorded.toml` in that directory. It records the item, the result, who (default: git's `user.name`), when (default: today), the commit checked out, the note, and the fingerprints of the item and of the items it links to. It refuses an item that does not exist, a project that keeps no results, and a first path that is a JSON or YAML file.

%req[results.stale]
A result with fingerprints shall be stale once one of the items they are of has changed: it then belongs to no item, and `check` warns that it is to be recorded again.

%req[results.rendered]
A generated coverage page (`render.generated.coverage`) shall also show, when there are results, per implementation how many items passed, failed and are untested, with links to the items that failed. `render` takes `--results` as `coverage` does.

%req[verification.records]
An item whose verification method is not a test (analysis, inspection, demonstration) shall be verified by a record of that verification: a result a person recorded with `skein result`, of the item or of a procedure that links to it, with its evidence, the files that show it (`--evidence PATH`, more than once), kept in git with the project's results. `check` warns about evidence that is not in the project.

%req[verification.coverage]
`skein coverage` shall count, for each verification method the items name, how many of those items are verified as the method requires, and list those that are not: an item verified by `test` by a passing result of a test, in any implementation; any other by a passing result a person recorded that is not stale.

%req[results.unmatched]
A result that belongs to no item shall be listed by `coverage`, and reported by `check` as a warning for the results the project keeps; it is not a problem.
