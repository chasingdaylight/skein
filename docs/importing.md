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
