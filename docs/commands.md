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

A command that reads other repositories (`check`, `trace`, `coverage`, `export`, `render`) reads each at the commit `.skein/network.toml` records. `--current` reads each at the commit its checkout has checked out, and `--working` reads its files as they are, committed or not: see [other repositories](repositories.md).

## `skein check`

Reads the configuration, the schema, every item and every citation, and reports everything that is wrong. With no problems it prints one line that counts what it read. This is the command for continuous integration.

What could not be checked, such as the items of another repository that is not at hand, is a warning: `file:line:column: warning: message`, shown with the problems. Warnings alone do not fail a check.

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

The project itself is not changed. `DIR` is created when needed and is best kept out of git.

### `--format html`: the site itself

`skein render --format html --out DIR` writes a static site that needs no site generator: each document and item file as an HTML page, with its markers as anchors and its references as links, the images beside them, a front page that lists the pages, and a page of all items with what links to each and what refers to it.

Every link is relative and the styles are inside each page, so `DIR` can be served from any address (GitHub Pages, a file share) or opened straight from disk. The pages follow the reader's light or dark setting.

### Generated pages

A document can ask for a page that skein makes from the project, in a fenced code block of the language `skein`. `skein render` replaces the block with the page, in both formats; elsewhere (on GitHub, in an editor) the request shows as the code it is.

````markdown
```skein
list term
```
````

| Request | Gives |
| --- | --- |
| `list [TYPE...] [category=C] [status=S] [profile=P] [ATTRIBUTE=V]` | A table of the items that pass every condition, with category, status and first paragraph. `list term` is a glossary. |
| `matrix LINKTYPE [conditions]` | Each item the link type may point to, with the items that link to it; the gaps marked **none**. A traceability matrix. |
| `coverage [profile=P]` | The coverage table, with links to the items that are not covered. |

A request skein cannot read becomes a note in its place, saying what is wrong.

### `--format document`: one file per document

`skein render --format document --out DIR` writes each document as one HTML file that stands alone, for delivery: no navigation, its images inside it, and a style sheet for printing (or saving as PDF from a browser).

### `--profile NAME`: for one profile

With `--profile NAME`, in any format, only the items of that profile (`.skein/profiles/`) are rendered: for example one stage of a language, or one software class. An item outside it is left out with its parts, references to it become plain words, and generated pages list only the profile's items.

## `skein move OLD NEW`

Gives an item another ID, everywhere the old one is used, in one step:

```text
$ skein move lex.keywords lex.kw
skein: lex.keywords is now lex.kw, with 2 parts: 6 places in 3 files
```

- **What is rewritten:** the item's marker or front matter, every reference to it (`%[lex.keywords]`) in items and in narrative text, every link to it, and every citation of it in code, tests and `.skein-cites` files.
- **Parts follow:** a part whose ID continues the old ID is renamed with it (`lex.keywords.as` becomes `lex.kw.as`). A part with an ID of its own is left as it is.
- **Item files:** a file named after its ID (`SRS-012.md`) is renamed too.
- **Reviews and approvals survive:** a rename changes no content, so what was reviewed stays reviewed and what was approved stays approved, under the new IDs.
- **Only whole IDs on the lines that name them** are replaced. `lex.token` is not touched inside `lex.token.kinds`, nor in a line of code that merely contains the same letters.

`skein move` refuses, and changes nothing, when the new ID is taken or is not a valid ID of the item's type. Look at the result with `git diff` before committing; nothing is committed for you.

## `skein baseline [NAME]`

Freezes the project as it is committed, as a git tag: a version of a specification, a delivered set of requirements.

```text
$ skein baseline v1.0 --message "As delivered to review."
skein: baseline v1.0 at 3f2a91c; share it with: git push origin v1.0
$ skein diff v1.0
```

- The tag is annotated, and its message says what the project held: its number of items and its coverage.
- It is refused while there are uncommitted changes, or while `skein check` reports problems: a baseline is a state others can build on.
- `skein diff` and `skein impact` compare against a baseline like any commit: what changed since v1.0, and what it reaches.
- Without a name, `skein baseline` lists the baselines, oldest first. Ordinary tags are not listed.

The tag is only made locally; push it to share it.

## `skein pin [NAME [REV]]`

Records in `.skein/network.toml` the commit of each other repository that the items are checked against: the commit `REV`, or the one its checkout has checked out. With a name, only that repository is pinned. For a repository pinned before, it says what changed there and which of the changed items this project refers to, so that someone can look at them before committing the record. It refuses a checkout with changes that are not committed, unless the commit is named. See [other repositories](repositories.md).

## `skein import doorstop DIR...`

Turns Doorstop documents into skein items, where they are; see [importing](importing.md).

## `skein import csv FILE --type TYPE --to DIR`

Makes an item file in `DIR` of each row of a CSV file; see [importing](importing.md).

## `skein review ID...` and `skein clear ID...`

Record that links have been reviewed; see [reviewing](reviewing.md). `review` takes the items whose links you looked at, `clear` the items that changed. `--all` takes every link.

## `skein approve ID...`

Records that someone approved these items as they are now; see [reviewing](reviewing.md). `--by NAME` says who (default: the name git has for the user), `--on DATE` when (default: today).

## `skein new TYPE [ID]`

Starts an item of a type.

```text
$ skein new srs
requirements/SRS-013.md
$ skein new rule lex.comment.block
%rule[lex.comment.block]
```

- **Numbered types** get the next free number when no ID is given: one more than the highest in use, counting removed items, so a number is never given twice.
- **Types with IDs joined by dots** need the ID, since only the author knows what it is about.
- **Where it goes:** a type with a source of item files gets its file there, with its front matter and no text, and the path is printed; `--to DIR` picks the source when there are several. A type written in documents gets its marker printed, to start a paragraph or list entry with.

`skein check` reports the new item as having no text until its text is written.

## `skein link FROM TYPE TO`

Adds a link of a type from one item to another:

```text
$ skein link c.one verifies lex.comment
skein: c.one verifies lex.comment
```

- **In a document**, the link goes in the item's marker: `%case[c.one verifies=lex.comment]`, or added to the values already there (`verifies=lex.token,lex.comment`).
- **In an item file**, it goes in the front matter: added to the key's list (`refines = ["SRS-001", "SRS-003"]`), or as a new key after the ID.
- **Refused**, with nothing written, is anything `skein check` would report: a link type the item cannot have, a target the link cannot point to, a removed target, a link to the item itself, or one that is there already.

## `skein lsp`

A language server for editors, on standard input and output. It works in the Markdown documents of a project and in the code and tests that cite its items.

- **Problems as you save:** what `skein check` reports is shown on the lines it concerns, in every file of the project, and updated whenever a file is saved.
- **Go to definition:** from the ID of an item to where it is declared, whether the ID stands in a reference (`%[lex.token]`), a link (`verifies=lex.token`), a citation in a test (`// spec: lex.token`) or plain text.
- **Find references:** every place that names an item: references, links and citations.
- **Hover:** the item's type, category and status, its text and its parts.
- **Completion:** item types after `%`, IDs in references and after a citation marker, and after the ID of a marker its categories, statuses, attributes and link types, then their values.
- **Rename:** renaming an item does what `skein move` does. Save your files first; the rename is made in them, and the editor shows them again.

Any editor with a Language Server Protocol client can use it. Tell the editor to start `skein lsp` for Markdown files (and for the source files that hold citations) with the project's directory as the root. For example, in Neovim:

```lua
vim.lsp.config('skein', { cmd = { 'skein', 'lsp' }, filetypes = { 'markdown' }, root_markers = { '.skein' } })
vim.lsp.enable('skein')
```

and in Helix's `languages.toml`:

```toml
[language-server.skein]
command = "skein"
args = ["lsp"]

[[language]]
name = "markdown"
language-servers = ["skein"]
```

The VS Code extension does not start the server yet.

## `skein help`, `skein version`

The usage text, and skein's version.

## In continuous integration

A CI job needs three lines: get skein, check, and report coverage.

```yaml
- name: skein
  run: |
    echo "::add-matcher::.github/skein-matcher.json"
    skein check
    skein coverage --markdown >> "$GITHUB_STEP_SUMMARY"
```

- **`skein check` fails the job** when the project has problems (exit status 1), and prints each as `file:line:column: error: message`.
- **Annotations on GitHub:** that form is one GitHub Actions can read. With the problem matcher below saved as `.github/skein-matcher.json`, each problem is shown on its line in the pull request. It needs the project to be at the root of the repository, since the paths are from the project's root.
- **`skein coverage` never fails the job:** it reports. `--markdown` puts the table in the job's summary.

```json
{
  "problemMatcher": [
    {
      "owner": "skein",
      "pattern": [
        {
          "regexp": "^(.+?):(\\d+):(\\d+): (error): (.*)$",
          "file": 1,
          "line": 2,
          "column": 3,
          "severity": 4,
          "message": 5
        }
      ]
    }
  ]
}
```

To get skein in the job, download the archive of a [release](https://github.com/chasingdaylight/skein/releases) for the runner's platform and check it against the release's `SHA256SUMS`; pin the version, so that a new skein never changes a job by itself.
