# The files of a project

A project is a repository with a `.skein/` directory at its root. This page describes the files in it that skein reads so far. All of them are TOML; one file declares one thing, and a file's name is the name of what it declares. A name is lowercase letters, digits, `-` and `_`, starting with a letter. A key that skein does not know is reported, so a misspelled key is never ignored in silence.

`skein check` reads all of this and reports every mistake with its file.

## `.skein/config.toml`

```toml
[project]
name = "example"

# Markdown documents whose paragraphs can be items
[[sources]]
path = "docs/spec"

# Markdown files that are one item each
[[sources]]
path = "docs/requirements"
kind = "items"
type = "srs"
```

| Key | Meaning |
| --- | --- |
| `project.name` | The project's name, for reports. |
| `template` | The templates the project uses: `"langspec"`, a list of names, or `[template.KEY]` tables with a `name` and options. See [templates](templates.md). |
| `project.id` | What other projects know this one by, whatever short name they give it: `"cesiumlang/cesium"`. |
| `forge.kind`, `forge.repository`, `forge.url` | Where the project's issues and pull requests are: `"github"`, `"owner/repo"`, and a server other than the public one. See [the forge](forge.md). |
| `results.paths` | The test results files the project keeps, or directories of them: see [test results](results.md). |
| `repositories` | The other repositories whose items this project's items refer to: see [other repositories](repositories.md). |
| `repositories.name` | The short name targets use before the colon: `compiler` in `%[compiler:lex.token]`. |
| `repositories.path` | A checkout on disk, from the project's root: `"../cesium-src"`. |
| `repositories.url` | An address git can fetch from, in place of a path. |
| `repositories.ref` | For a `url`: the branch or tag `--current` follows. |
| `repositories.site` | The address of its site, as `skein render --format html` writes it: references to its items link there. |
| `sources` | The places that hold items. |
| `sources.path` | A directory, from the project's root, with forward slashes. |
| `sources.kind` | `"documents"` (the default) or `"items"`. |
| `sources.type` | For `"items"`: the item type of a file that names none. |
| `sources.order_by` | For `"items"`: the attribute whose values give the order its files are rendered in, compared as dotted numbers, such as Doorstop's `level`. Without it, by path. |
| `sources.read_only` | `true` for a source that is imported, not edited, such as an external standard: `skein move`, `link` and `new` refuse to change its files. `check` reads it as any other. |
| `citations` | The places whose files cite items in comments. |
| `citations.name` | What the citations are: `"test"`, `"code"`. Coverage counts by this name. |
| `citations.path` | A directory, from the project's root; `"."` for all of it. |
| `citations.files` | The ends of the names of the files to read: `[".zig"]`, `["_test.c"]`. |
| `citations.marker` | The text that comes before the IDs on a line: `"// spec:"`. |
| `citations.to` | The item types the citations may name; leave out for any. |
| `citations.expected` | Every item of a `to` type should be cited by the set; coverage counts the ones that are not. |

```toml
[[citations]]
name = "test"
path = "tests"
files = [".zig"]
marker = "// spec:"
to = ["rule"]
```

Directories whose names start with a dot, and `zig-out`, `zig-pkg` and `node_modules`, are never read.

## `.skein/types/<name>.toml`: an item type

```toml
description = "A software requirement"
id = "numbered"
prefix = "SRS"
digits = 3
categories = ["functional", "performance"]
statuses = ["draft", "approved", "deprecated", "removed"]
tombstone = "removed"
verification = ["test", "analysis", "inspection", "demonstration"]

[attributes.priority]
type = "string"
values = ["low", "medium", "high"]
required = true

[attributes.rationale]
normative = false
```

| Key | Meaning |
| --- | --- |
| `description` | What the type is for. |
| `id` | `"hierarchical"` (the default): IDs like `lex.comment.line`. `"numbered"`: IDs like `SRS-012`, with `prefix` and at least `digits` digits (default 3). |
| `separator` | For numbered IDs: what stands between the prefix and the number. Default `"-"`; may be empty (`REQ001`). |
| `names` | For numbered IDs: `true` allows a name in the number's place (`SRS-PURPOSE`). |
| `categories` | The categories an item of the type is one of; leave out for none. |
| `statuses` | The lifecycle. Default: draft, approved, deprecated, removed. |
| `tombstone` | The status of a removed item, whose ID stays taken. Default `"removed"`, when the statuses have it. |
| `verification` | The verification methods an item of the type may name. |
| `approval` | The statuses an item may have only while it is approved as it is: see [reviewing](reviewing.md). As a table, `[approval]` with `statuses` and `roles`: the roles that must each approve. |
| `example` | A table that makes the type one of tested examples: see [writing items](writing-items.md#tested-examples). |
| `example.link` | The link type an example inside an item counts as, to that item: `"shows"`. |
| `example.rejects` | The category of an example that must be rejected. Default `"rejects"`. |
| `example.extensions` | The file name extension of each language's examples: `{ cesium = ".csm" }`. Default: the language. |
| `attributes.<name>.type` | `"string"` (the default), `"integer"`, `"boolean"` or `"date"`. |
| `attributes.<name>.values` | The values a string attribute may take. |
| `attributes.<name>.required` | Whether every item of the type must have it. |
| `attributes.<name>.normative` | Whether a change to it changes the item's fingerprint. |
| `attributes.<name>.list` | Whether it holds several values: `classes=A,B,C`, or `classes = ["A", "B"]` in front matter. A profile's `where.classes = "C"` selects the items that have `C` among them. |

An empty file is a valid type: hierarchical IDs, no categories, the default statuses, no attributes.

## `.skein/links/<name>.toml`: a link type

```toml
description = "A test verifies a rule"
from = ["test"]
to = ["rule"]
expected = true
```

| Key | Meaning |
| --- | --- |
| `description` | What the link means. |
| `from` | The item types a link of this kind may start at; leave out for any. |
| `to` | The item types it may point to; leave out for any. |
| `required` | Every item of a `from` type must have one. |
| `expected` | Every item of a `to` type should be pointed to by one; coverage counts the ones that are not. `expected = { where = { verification = "test" } }` expects it only of the items whose attribute (or `verification`, `category`, `status`) has that value, and `expected = { profile = "P" }` of the items of a profile. The same goes for `citations.expected`. |
| `review` | Links of this type are reviewed: see [reviewing](reviewing.md). |
| `open` | An issue or pull request a link of this type points to must be open: see [the forge](forge.md). |
| `counts_as` | A link of this type counts as one of that type, for coverage: a tailoring as good as compliance. |
| `excuses` | A link of this type excuses its target from the coverage of that type: shown as waived, counted neither way. |

A standard's requirements, imported into a read-only source, are covered by the project's links to them; waivers and deviations are item types of the project's, linked to the requirement they relax:

```toml
# .skein/links/waives.toml
from = ["waiver"]
to = ["swe"]
excuses = "complies-with"   # or counts_as = "complies-with"
```

A waiver counts only while it is in force: not removed, and approved when its type asks for approval (`approval = ["approved"]`).

## `.skein/profiles/<name>.toml`: a profile

A profile is a named selection of items. An item is in it when it passes every condition given.

```toml
description = "What the first stage of the language defines"
types = ["rule"]
statuses = ["approved"]

[where]
stage = "s0"
```

| Key | Meaning |
| --- | --- |
| `description` | What the profile selects. |
| `types` | Item types; leave out for any. |
| `categories` | Categories; leave out for any. |
| `statuses` | Statuses; leave out for any. |
| `where.<attribute>` | A value, or an array of values, the attribute must have one of. |
