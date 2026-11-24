# Tutorial: Skein in a project that has code

This tutorial adds Skein to a project that already exists: a small C program, `tally`, which counts the lines, words and bytes of files as `wc` does. By the end its requirements are written down, its code and tests say which requirements they implement and verify, and Skein answers what is tested, what a change reaches, and what the requirements look like as a site. It takes about fifteen minutes.

You need the `skein` program on your `PATH` (see [getting it](index.md#getting-it)) and git. Every command below was run as shown; your fingerprints and commits will differ.

## The project

```text
tally/
  src/count.c
  src/main.c
  tests/test_count.c
  tests/test_main.c
```

It is a git repository. Nothing in it knows about Skein yet.

## 1. Start

In the root of the repository:

```text
$ skein init
skein: a project in ., with 0 documents to start from; 'skein check' checks it; AGENTS.md tells coding agents about Skein
```

`skein init` writes two files. `.skein/config.toml` is the project's configuration, and the directory `.skein/` is what makes the repository a Skein project:

```toml
# where the items are: Markdown documents whose paragraphs can be items
[[sources]]
path = "docs"
```

`AGENTS.md` tells coding agents how this project keeps its requirements, so that they cite them as people do (`skein agents` writes it again, or into `CLAUDE.md`). Keep it or delete it.

## 2. Say what a requirement is

Skein has no built-in notion of a requirement: a project declares the kinds of items it has. One file in `.skein/types/` declares one item type. Here the type is `req`, with numbered IDs:

```toml
# .skein/types/req.toml
description = "A requirement of tally"
id = "numbered"
prefix = "REQ"
```

So a requirement is `REQ-001`, `REQ-002` and so on. An empty file would also be a valid type, with IDs like `count.lines`; see [project files](project-files.md) for everything a type can say.

## 3. Write the requirements

Requirements are written in a Markdown document under `docs/`, where the configuration looks. A paragraph that starts with a marker, `%req[ID]`, is an item; every other paragraph is narrative, which explains:

```markdown
# Requirements

tally counts the lines, words and bytes of files, as `wc` does.

## Counting

%req[REQ-001] tally shall count the lines, words and bytes of each file named on its command line.

%req[REQ-002] With no file named, tally shall count its standard input.

## Output

%req[REQ-003] tally shall print one line for each file, and a line of totals when there are several.

%req[REQ-004] A file that cannot be read shall be reported on standard error, and tally shall exit with status 1 after counting the others.
```

The document reads as a document on GitHub, in an editor or on paper, and `grep '%req\['` finds every requirement. Give the project a name for the reports while you are in the configuration:

```toml
[project]
name = "tally"
```

## 4. Let the code and the tests cite them

Code and tests are not items. They say which items they implement or verify in a comment, with a marker the project chooses. Add two citation sets to `.skein/config.toml`:

```toml
# the code says which requirements it implements
[[citations]]
name = "code"
path = "src"
files = [".c", ".h"]
marker = "// implements:"
to = ["req"]

# the tests say which they verify; every requirement should have one
[[citations]]
name = "test"
path = "tests"
files = [".c"]
marker = "// verifies:"
to = ["req"]
expected = true
```

Then write the comments where they belong:

```c
// src/count.c
// implements: REQ-001
struct counts count(FILE *in) {
```

```c
// src/main.c
// implements: REQ-002, REQ-003, REQ-004
int main(int argc, char **argv) {
```

```c
// tests/test_count.c
// verifies: REQ-001
void test_counts_a_line(void) {
```

```c
// tests/test_main.c
// verifies: REQ-002, REQ-03
void test_reads_stdin(void) {
```

The last one has a typing mistake, and `skein check` finds it:

```text
$ skein check
tests/test_main.c:1:23: error: the citation names 'REQ-03', and there is no such item
skein: 1 problem
```

With `REQ-003` written in its place:

```text
$ skein check
skein: tally: no problems (4 items of 1 types, 0 link types, 0 profiles, 7 citations)
```

`skein check` exits with status 1 when there are problems, so it can fail a build: see [in continuous integration](commands.md#in-continuous-integration).

## 5. What is tested

`expected = true` on the test citations says that every requirement should be verified by a test. `skein coverage` counts:

```text
$ skein coverage
Coverage of tally

test citations of req items: 3 of 4 (75%)
  without:
    REQ-004
```

`skein trace` shows one item with everything around it:

```text
$ skein trace REQ-003
REQ-003  (req, draft)
  docs/requirements.md:13
  fingerprint 69a74af9f56ee09662c9ec8a7e74b5c9

Cited by:
  code  src/main.c:3
  test  tests/test_main.c:1
```

The fingerprint is a hash of what the requirement says, used to notice when it changes (below).

## 6. Add a requirement and a test

`skein new` gives the next free number. For a type written in documents it prints the marker to start the paragraph with:

```text
$ skein new req
%req[REQ-005]
```

```markdown
%req[REQ-005] `tally --help` shall print how to use it and exit with status 0.
```

With a test for `REQ-004` (`// verifies: REQ-004` in `tests/test_errors.c`), the gap moves to the new requirement:

```text
$ skein coverage
Coverage of tally

test citations of req items: 4 of 5 (80%)
  without:
    REQ-005
```

Commit the requirements, the configuration and the comments together, as any other change.

## 7. When a requirement changes

Say the totals line is to be labeled. Change the text of `REQ-003`, and before committing ask what changed and what it reaches:

```text
$ skein diff
Changes from HEAD to the working tree

Changed (1):
  REQ-003  (req)  content  docs/requirements.md:13

$ skein impact
Impact of the changes from HEAD to the working tree

Changed (1):
  REQ-003  (req)  content  docs/requirements.md:13

Cited in (2):
  src/main.c:3  (code)  REQ-003
  tests/test_main.c:1  (test)  REQ-003
```

The code and the test that cite the requirement are what a reviewer of the change looks at. Both commands also take commits and baselines (`skein diff v1.0`). For a project that must show that its citations were looked at after each change, a citation set can ask for reviews (`review = true`), and `skein check` then reports a citation of a requirement that changed since it was reviewed: see [reviewing](reviewing.md).

## 8. Publish, and check on every change

```text
$ skein render --format html --out site
skein: 3 pages rendered to site
```

`site/` is a static site that needs no generator: the requirements document with every ID linked, and a page of all items with what cites each. Open `site/index.html`, or serve the directory anywhere. Keep it out of git (`site/` in `.gitignore`) and build it in CI, which also runs `skein check` and can report `skein coverage --markdown` in the job's summary: [in continuous integration](commands.md#in-continuous-integration) has the lines for GitHub Actions and GitLab CI.

In VS Code, the extension `chasingdaylight.skein` shows what `skein check` reports as you save, goes from a citation to its requirement, and lists the items in a tree.

## Where next

- **Tests as items, design, links between levels:** a project can have more item types (tests, design elements, needs) and typed links between them (`verifies`, `refines`), with links that must be there and links that are expected. See [project files](project-files.md) and [writing items](writing-items.md).
- **A standard to follow:** if the project works to a standard (ISO/IEC/IEEE 29148, NASA's NPRs), start from a [template](templates.md) instead of writing the types: `skein init --template iso29148`.
- **Requirements kept elsewhere:** [importing](importing.md) brings in Doorstop documents and spreadsheets.
- **Planning the work:** [the other tutorial](tutorial-planning.md) starts from a project with no code, and plans it.
