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

Mentioned in:
  spec/lex.md:2

Cited by:
  test  tests/comment.zig:1

Above (all it rests on): lex.token

Below (all that rests on it): c.comment, c.other
```

A link points up, from an item to what it rests on: a test to the rule it verifies, a requirement to the one it refines. So **above** an item is everything its links lead to, however many links away, and **below** it is everything that leads to it: what may need another look when the item changes.

`--json` gives the same as JSON: the item (with its text), and the IDs above and below.

## `skein coverage`

Counts, of the items that should be linked to or cited, how many are, and lists the ones that are not. An item with [parts](writing-items.md#parts-items-inside-an-item) also counts when every one of its parts does:

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

Removed items are not counted. `--profile NAME` counts only the items of that profile (`.skein/profiles/`), for example one stage of a language or one software class. `--json` gives the counts and the lists as JSON. `--markdown` gives them as a Markdown table with the uncovered items folded away, for the summary of a CI job (`skein coverage --markdown >> "$GITHUB_STEP_SUMMARY"`) or a comment on a pull request.

Coverage reports; it does not fail. Its exit status is 0 whatever the numbers are.

## `skein diff [REV [REV]]`

Shows which items were added, removed or changed since a commit: by default the last one (`HEAD`), compared with the files as they are. `REV` is anything git takes for a commit: a hash, a tag, a branch, `HEAD~3`. With two, the first is compared with the second and the working tree is not looked at.

```text
Changes from v0.3 to the working tree

Added (1):
  lex.new  (rule)  spec/lex.md:13

Removed (1):
  lex.gone  (rule)

Changed (2):
  lex.token  (rule)  content  spec/lex.md:5
  lex.space  (rule)  status: approved -> deprecated, attributes  spec/lex.md:8
```

The **content** of an item has changed when its fingerprint is different, so a paragraph that was only rewrapped is not listed. A change to a part is also a change to the content of the item that contains it. A different status, links, attributes or verification method are each named. An item that was given the status of a removed item counts as removed.

## `skein impact [REV]`

The same changes, and what they reach in the project as it is now:

```text
Look again at (2):
  c.token  (case)  rests on lex.token  spec/lex.md:16
  c.deep  (case)  rests on lex.token  spec/lex.md:19

Links now suspect (1):
  c.token  verifies lex.token

Cited in (1):
  tests/token.zig:1  (test)  lex.token
```

- **Look again at:** every item below an item that was removed or whose content changed, however many links away, and every item whose text refers to it.
- **Links now suspect:** the reviewed links to those items; see [reviewing](reviewing.md).
- **Cited in:** the tests and code that cite them: the tests to run again, the code to read again.

Both commands take `--json`, and `--markdown` for a summary to put in a pull request. They need git: the earlier state of the project is taken out of the repository.

## `skein export [WHAT]`

Writes the project's graph to standard output, for other tools.

| `WHAT` | Gives |
| --- | --- |
| `json` (the default) | Everything as one JSON document: the item types and link types, and every item with its status, fingerprint, attributes, links both ways with their review state, references, approvals, citations and text. |
| `items` | CSV, one row per item: ID, type, category, status, verification, the item it is a part of, file, line, fingerprint, a column for each attribute, and the text. |
| `links` | CSV, one row per link: from, its type, the link type, to, its type, and the review state. A traceability matrix in its long form, ready for a pivot table. |
| `citations` | CSV, one row per citation: the citation set, file, line, the item and its type. |

`--profile NAME` exports only the items of that profile, with their links and citations.

The output is the same for the same project, byte for byte, so an export can be kept and compared. The JSON is what `skein trace --json` gives for one item, for all of them.

## `skein render --out DIR`

Writes the documents and item files of the project as Markdown for a site generator (Quartz, MkDocs, Jekyll, Hugo), into `DIR`, each under the path it has in the project. Use it as a step before the generator runs, and point the generator at `DIR`.

A source such as

```markdown
%rule[lex.comment syntax final] A comment is not a %[lex.token]; see %[lex.space white space].
```

is written as

```markdown
<a id="lex.comment"></a>**[lex.comment](#lex.comment)** *(syntax, final)* A comment is not a [lex.token](terms.md#lex.token); see [white space](#lex.space).
```

- **Markers** become an anchor and the ID, linked to itself, so every item can be linked to and its ID can be copied from the page.
- **References** become links to the item, in the same document or another, in items and in narrative text alike.
- **Item files** get YAML front matter with the ID as the title, which site generators read, in place of the TOML front matter.
- **Everything else** is written unchanged. Only Markdown files are written; images and other files stay where the generator already finds them.

The project itself is not changed. `DIR` is created when needed and is best kept out of git. skein rendering HTML by itself is planned; this command is for projects that already publish with a generator.

## `skein import doorstop DIR...`

Turns Doorstop documents into skein items, where they are; see [importing](importing.md).

## `skein import csv FILE --type TYPE --to DIR`

Makes an item file in `DIR` of each row of a CSV file; see [importing](importing.md).

## `skein review ID...` and `skein clear ID...`

Record that links have been reviewed; see [reviewing](reviewing.md). `review` takes the items whose links you looked at, `clear` the items that changed. `--all` takes every link.

## `skein approve ID...`

Records that someone approved these items as they are now; see [reviewing](reviewing.md). `--by NAME` says who (default: the name git has for the user), `--on DATE` when (default: today).

## `skein help`, `skein version`

The usage text, and skein's version.
