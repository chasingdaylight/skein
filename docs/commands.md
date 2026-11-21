# Commands

```text
skein <command> [options]
```

Every command that works on a project finds it from the current directory: the nearest directory, here or above, that has a `.skein/`. `--root DIR` starts the search elsewhere.

| Exit status | Meaning |
| --- | --- |
| 0 | Done; the answer is on standard output. |
| 1 | The project has problems; they are on standard error, one per line, as `file:line:column: error: message`. |
| 2 | The command was not used as it must be, or there is no project. |

## `skein check`

Reads the configuration, the schema, every item and every citation, and reports everything that is wrong. With no problems it prints one line that counts what it read. This is the command for continuous integration.

What it reports is listed in [writing items](writing-items.md) and [reviewing](reviewing.md).

## `skein trace ID`

Shows one item with everything around it:

```text
lex.comment  (rule, syntax, draft)
  spec/lex.md:4
  fingerprint 5f22a849198320cdad1f1067124515c1
  stage = s0

Links to:
  see lex.token (term)

Linked from:
  verifies c.comment (case)  [reviewed]
  verifies c.other (case)  [never reviewed]

Refers to: lex.token

Referred to by: c.comment

Cited by:
  test  tests/comment.zig:1

Above (all it rests on): lex.token

Below (all that rests on it): c.comment, c.other
```

A link points up, from an item to what it rests on: a test to the rule it verifies, a requirement to the one it refines. So **above** an item is everything its links lead to, however many links away, and **below** it is everything that leads to it: what may need another look when the item changes.

`--json` gives the same as JSON: the item (with its text), and the IDs above and below.

## `skein coverage`

Counts, of the items that should be linked to or cited, how many are, and lists the ones that are not:

```text
Coverage of example

verifies links to rule items: 2 of 4 (50%)
  syntax: 2 of 2 (100%)
  legality: 0 of 2 (0%)
  without:
    lex.c
    lex.d

test citations of rule items: 2 of 4 (50%)
  syntax: 1 of 2 (50%)
  legality: 1 of 2 (50%)
  without:
    lex.b
    lex.c
```

What should be is what the project marks `expected = true`:

- a link type (`.skein/links/`): every item of its `to` types should be pointed to by a link of that type;
- a citation set (`[[citations]]` in `.skein/config.toml`): every item of its `to` types should be cited by the set.

Removed items are not counted. `--profile NAME` counts only the items of that profile (`.skein/profiles/`), for example one stage of a language or one software class. `--json` gives the counts and the lists as JSON.

Coverage reports; it does not fail. Its exit status is 0 whatever the numbers are.

## `skein review ID...` and `skein clear ID...`

Record that links have been reviewed; see [reviewing](reviewing.md). `review` takes the items whose links you looked at, `clear` the items that changed. `--all` takes every link.

## `skein approve ID...`

Records that someone approved these items as they are now; see [reviewing](reviewing.md). `--by NAME` says who (default: the name git has for the user), `--on DATE` when (default: today).

## `skein help`, `skein version`

The usage text, and skein's version.
