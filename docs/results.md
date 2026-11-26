# Test results

Skein reads test results and says, per item, whether its tests passed. It runs no tests: the project's test driver, or a person carrying out a procedure, writes the results.

## A results file

TOML, JSON or YAML, by its extension; the fields are the same in each:

```toml
[[result]]
test = "lexer: line comment"
file = "tests/lex/comment.zig"
result = "pass"
implementation = "cesium0"
version = "0.3.1"

[[result]]
item = "tp.lex.inspect-comments"
result = "pass"
implementation = "cesium0"
note = "Checked the listing in section 2 by hand."
```

| Field | Meaning |
| --- | --- |
| `result` | `pass`, `fail` or `skip`. Required. |
| `test` | The test's name, for lists. |
| `file` | The file of the test, from the project's root. The result belongs to every item cited in that file. |
| `item` | An item the result is of, such as a procedure of a test plan: the result belongs to it and to the items its links point to. |
| `items` | Items the result belongs to directly, for a test whose code cannot cite them. |
| `implementation`, `version` | What produced it: each implementation is counted on its own. |
| `note` | Anything worth keeping with it. |

A test driver can append to a TOML file as it runs, one `[[result]]` table at a time. JSON takes an array of results, or an object with a `result` array; YAML a list, or a `result:` list.

## From a test runner: JUnit XML and TAP

Skein also reads what test runners write themselves: JUnit XML (`.xml`), which most CI systems and many runners write, and TAP (`.tap`). Neither has a place for the implementation, so a run's file is given with what produced it:

```text
skein coverage --results junit.xml --implementation cesium0 --implementation-version 0.3.1
```

`--implementation` and `--implementation-version` apply to the results of `--results` that name none.

In JUnit XML, each `testcase` is a result: failed with a `failure` or `error` element (its `message` is the note), skipped with `skipped`, passed otherwise. Its file is the `file` attribute of the case, else of the nearest `testsuite`, as many runners write it. `property` elements give what JUnit has no attribute for, on a case or a suite (the nearest counts):

```xml
<testcase name="inspect the listing" file="tests/listing.zig">
  <properties>
    <property name="item" value="tp.lex.inspect-comments"/>
    <property name="items" value="lex.comment, lex.token"/>
  </properties>
</testcase>
```

`implementation` and `version` may be properties of a suite as well. In TAP, each `ok` or `not ok` line is a result, indented subtests too; `# SKIP` and `# TODO` make it skipped, and `Bail out!` is a failed result. TAP names no files, so comments and YAML blocks do:

```text
TAP version 14
# implementation: cesium0
# file: tests/lex/comment.zig
ok 1 - line comment
not ok 2 - block comment
  ---
  file: tests/lex/block.zig
  items: [lex.comment.block]
  ...
```

A `# file:` comment applies to the tests after it; a YAML block to the test before it. In both formats files are read with forward slashes and without a leading `./`, from the project's root.

## Kept, or given for one command

A project that keeps its results, for a test report it must file, names where:

```toml
# .skein/config.toml
[results]
paths = ["verification/results"]
```

Every results file under those paths (`.toml`, `.json`, `.yaml`, `.yml`, `.xml`, `.tap`) is read by `check`, `trace` and `coverage`. A CI run's results need not be kept: `skein coverage --results run.json` reads them for that command alone, and `--results` may be given more than once.

## A result a person obtained

A procedure of a test plan carried out by hand, an inspection, an analysis: someone records how it went.

```text
$ skein result tp.lex.inspect-comments pass --note "Checked the listing in section 2."
skein: recorded that tp.lex.inspect-comments passed, by A. Tester, in verification/results/recorded.toml
```

It goes into the results the project keeps (the first of `[results] paths`), with who (`--by`, default git's `user.name`), when (`--on`, default today), the commit checked out, and the fingerprints of the procedure and of what it verifies. As an approval does, it then goes stale once one of them changes: the result says nothing of the item any more, and `check` warns that it is to be recorded again.

## Verified as each item's method requires

An item says how it is verified (`verification=inspection`, among the methods its type declares). `skein coverage` counts, per method, the items verified as that method requires: one verified by `test` by a passing result of a test; one verified by analysis, inspection or demonstration by a passing result a person recorded, of it or of a procedure that links to it, that is not stale.

```text
verified as their method requires:
  test: 40 of 42 (95%)
    not verified:
      lex.comment
      lex.keywords.as
  inspection: 3 of 3 (100%)
```

A record can name the files that show it, a report or a log, kept in the repository:

```text
skein result tp.inspect pass --evidence reports/listing-review.pdf
```

`check` warns when such a file is not in the project.

## What Skein says of them

Per implementation, an item **passes** when every result that belongs to it passed, **fails** when one failed, and is **untested** when none belongs to it or all were skipped.

```text
$ skein coverage --results run.toml
...
results (cesium0 0.3.1): 40 of 47 passed, 2 failed, 5 untested
  failed:
    lex.comment
    lex.keywords.as
  untested:
    ...
```

The items counted are those of the types a citation set expects to be cited, and any that have results. A generated coverage page (a ```` ```skein ```` block with `coverage`) shows the same, with links to the items that failed; `Skein render --results FILE` gives it a run's results. `Skein trace ID` shows an item's verdict and its results per implementation. A result that belongs to no item (its file cites nothing, the items it names do not exist) is listed by `coverage`, and `check` warns about it for kept results.
