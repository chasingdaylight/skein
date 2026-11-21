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
| `sources` | The places that hold items. |
| `sources.path` | A directory, from the project's root, with forward slashes. |
| `sources.kind` | `"documents"` (the default) or `"items"`. |
| `sources.type` | For `"items"`: the item type of a file that names none. |

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
| `categories` | The categories an item of the type is one of; leave out for none. |
| `statuses` | The lifecycle. Default: draft, approved, deprecated, removed. |
| `tombstone` | The status of a removed item, whose ID stays taken. Default `"removed"`, when the statuses have it. |
| `verification` | The verification methods an item of the type may name. |
| `attributes.<name>.type` | `"string"` (the default), `"integer"`, `"boolean"` or `"date"`. |
| `attributes.<name>.values` | The values a string attribute may take. |
| `attributes.<name>.required` | Whether every item of the type must have it. |
| `attributes.<name>.normative` | Whether a change to it changes the item's fingerprint. |

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
| `expected` | Every item of a `to` type should be pointed to by one; coverage counts the ones that are not. |

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
