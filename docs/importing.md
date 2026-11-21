# Importing

## From Doorstop

```text
skein import doorstop docs/sys docs/srs docs/des docs/tst
```

Each directory named is a Doorstop document (it has a `.doorstop.yml`). The import changes it in place:

- every item (`SRS-001.md`, or `SRS-001.yml`) is rewritten as a skein item file, `SRS-001.md`, with TOML front matter;
- `.doorstop.yml` becomes an item type, `.skein/types/srs.toml`;
- the directory is added to the sources in `.skein/config.toml`, which is made when the repository is not a skein project yet;
- a link type `parent` is made, with `review = true`.

Because the files stay where they are, git shows each item's history through the import. **Commit before importing**: the import is then one diff to look over, and `git checkout .` undoes it. Nothing but the documents named and `.skein/` is touched; a file in the directory whose name does not start with the document's prefix is left alone.

### What becomes of what

| Doorstop | skein |
| --- | --- |
| the item's file name (`SRS-001`) | its `id` |
| `prefix`, `digits`, `sep` | the item type's numbered IDs (`prefix`, `digits`, `separator`) |
| an item named instead of numbered (`SRS-PURPOSE`) | allowed by `names = true` in the item type |
| `active: false` | `status = "removed"` |
| `links` | `parent` links |
| a link with a stamp | recorded as reviewed, as its target is now |
| `normative`, `derived`, `level`, `ref` | attributes of the same names (the booleans only where they differ from Doorstop's defaults) |
| `references` | the attribute `references`: the paths, separated by commas |
| `category` | the item's category, when every active item of the document has one; otherwise the attribute `doorstop-category` |
| `status`, and any attribute named like a key skein reads itself | an attribute with `doorstop-` before its name (`doorstop-status`) |
| every other attribute | an attribute of the same name |
| the attributes the document lists as `reviewed` | attributes marked `normative = true`, so that a change to them changes the item's fingerprint |
| `header` and `text` (items kept as YAML) | a heading and the text |
| `reviewed` (the item's own stamp) | left out |

### Reviews

Doorstop's stamps are hashes that only Doorstop can compute, so they cannot be carried over one for one. A link that had a stamp is recorded as reviewed against its target as it is at the import. That is right when Doorstop reported no suspect links beforehand, so **run `doorstop` first and clear what it reports**, then import. A link that had no stamp is left for `skein review`.

### Afterwards

Run `skein check`. Things to look at by hand:

- `doorstop-status`: Doorstop projects often keep a status of their own. If it is the item's lifecycle, make its values the item type's `statuses` and rename the key to `status` in the items.
- `verification-method` or the like: skein has `verification`, with the methods the item type allows.
- Doorstop's `references` point from an item to the code. skein reads the other direction, a citation in the code (`// Implements SRS-012.`), which cannot go stale unnoticed; see [writing items](writing-items.md).

## From a CSV file

```text
skein import csv requirements.csv --type srs --to docs/requirements
```

Each row becomes an item file in the directory: for requirements that arrive from a spreadsheet or an export of another tool, and for a standard the project must comply with, kept as items of its own that the project's items link to.

The first row names the columns:

| Column | Becomes |
| --- | --- |
| `id` (or the one `--id-column` names) | the item's ID, and its file's name |
| `text` (or the one `--text-column` names) | the item's text |
| `status`, `category`, `verification` | that |
| a column named after a link type | links: the IDs in the cell, separated by commas, semicolons or spaces |
| any other column | an attribute, named as the column in lowercase, with `-` for spaces |

Empty cells are left out. Names are matched without regard to case, so `ID` and `Text` are found. The file is CSV as spreadsheets write it: fields in quotes may hold commas, quotes (doubled) and line ends; semicolons are taken as the delimiter when the first line has more of them than commas.

When the project has no item type of the name given, one is made: with an attribute for each such column, and the ID scheme the IDs show (`SWE-013`: numbered; `sys.start`: hierarchical). When it has one, the type is left as it is, and `skein check` says what the items do not fit. The directory is added to the project's sources unless it is one already.

Nothing is written unless every row can be an item. An item file that is already there stops the import, unless `--replace` is given: that is how a newer export of the same list is brought in, and `git diff` then shows what changed in it.
