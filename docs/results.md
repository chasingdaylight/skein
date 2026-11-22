# Test results

skein reads test results and says, per item, whether its tests passed. It runs no tests: the project's test driver, or a person carrying out a procedure, writes the results.

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

## Kept, or given for one command

A project that keeps its results, for a test report it must file, names where:

```toml
# .skein/config.toml
[results]
paths = ["verification/results"]
```

Every results file under those paths is read by `check`, `trace` and `coverage`. A CI run's results need not be kept: `skein coverage --results run.json` reads them for that command alone, and `--results` may be given more than once.

## A result a person obtained

A procedure of a test plan carried out by hand, an inspection, an analysis: someone records how it went.

```text
$ skein result tp.lex.inspect-comments pass --note "Checked the listing in section 2."
skein: recorded that tp.lex.inspect-comments passed, by A. Tester, in verification/results/recorded.toml
```

It goes into the results the project keeps (the first of `[results] paths`), with who (`--by`, default git's `user.name`), when (`--on`, default today), the commit checked out, and the fingerprints of the procedure and of what it verifies. As an approval does, it then goes stale once one of them changes: the result says nothing of the item any more, and `check` warns that it is to be recorded again.

## What skein says of them

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

The items counted are those of the types a citation set expects to be cited, and any that have results. A generated coverage page (a ```` ```skein ```` block with `coverage`) shows the same, with links to the items that failed; `skein render --results FILE` gives it a run's results. `skein trace ID` shows an item's verdict and its results per implementation. A result that belongs to no item (its file cites nothing, the items it names do not exist) is listed by `coverage`, and `check` warns about it for kept results.
