# Fingerprints, reviews, suspect links and approvals

When a requirement changes, the items derived from it and the tests that verify it may no longer be correct. skein finds those places: a link can record the content of its target at the time the link was last reviewed, and `skein check` reports the link as suspect once the content of the target has changed.

## Fingerprints

Every item has a fingerprint: a hash of its content.

| Part of it | Not part of it |
| --- | --- |
| The own text of the item | Its status |
| Its type and its category | Its links |
| The attributes its type marks `normative = true` | Its other attributes |
| The names and fingerprints of its parts, in order | Its ID and where it is written |

Fingerprints form a tree, like the hashes of files and directories in git. An item with [parts](writing-items.md#parts-items-inside-an-item) is hashed over its own text and, for each part, the name and the fingerprint of the part; the text of the parts is not hashed again. So a change to a part changes the fingerprint of that part, of the item that contains it, and of every item above that, and of no other item. As with a file in git, the ID of an item is not part of its own fingerprint, but it is part of the fingerprint of the containing item: renaming a part changes the containing item and not the part. The name that is hashed is the ID of the part relative to the containing item (`.as` for `lex.keywords.as` in `lex.keywords`), so renaming only the containing item changes nothing. The status of a part is not hashed.

The text is hashed without its layout: runs of spaces and line endings count as one space, so rewrapping a paragraph, changing line endings or re-indenting a list changes nothing. Inside code blocks the lines are kept, because there they can matter.

## Reviewed links

A link type asks for reviews in its file:

```toml
# .skein/links/verifies.toml
from = ["test"]
to = ["rule"]
review = true
```

For a link of such a type, `skein check` reports:

- a link that **was never reviewed**, and
- a **suspect** link: its target has changed since the review.

Two commands record a review. Both take IDs, or `--all`:

| Command | Records as reviewed | When |
| --- | --- | --- |
| `skein review ID...` | The links **of** these items. | You have looked at your item against what it points to. |
| `skein clear ID...` | The links **to** these items. | An item changed, and you have looked at everything that points to it. |

Link types without `review = true` are never reported, so a project chooses which relations need this care.

## Where the records are

Under `.skein/reviews/`, never in the items or beside the documents, so the sources hold no hashes. There is one file per document, and one per directory of item files, each with one sorted line per link:

```toml
# .skein/reviews/spec/tests.md.toml
"t.lex.comment".verifies."lex.comment.line" = "9f2c41d0a6b7c8e9f0a1b2c3d4e5f607"
```

skein writes these files; no one edits them by hand. They are committed with the change that was reviewed, so a pull request shows which links its author looked at. Two branches conflict in them only where both reviewed links of the same document. A record of a link that no longer exists is dropped when its file is next written.

## Approvals

An approval records, in git, that a named person approved an item as it was on a given day:

```text
skein approve SRS-012 --by "A. Reviewer"
```

`--by` may be left out where git knows the user's name (`git config user.name`), and `--on 2027-03-01` gives a day other than today.

An approval applies to the content the item had at that time, identified by its fingerprint. When the item changes, the record is kept and shows what was approved, but the item is no longer approved. `skein trace` shows each approval and whether it applies to the current content.

An item type can make a status depend on it:

```toml
# .skein/types/srs.toml
approval = ["approved"]
```

Then `skein check` reports an item that has the status `approved` without an approval of its current content. So a requirement cannot be changed and stay "approved" unnoticed: either it is approved again, or its status goes back.

The records are under `.skein/approvals/`, in files named as the review records are, with one line per item and approver:

```toml
# .skein/approvals/requirements.toml
"SRS-012"."A. Reviewer" = { on = 2027-03-01, fingerprint = "9f2c41d0a6b7c8e9f0a1b2c3d4e5f607" }
```

Several people can approve one item. Approving again replaces that person's earlier record; git keeps the history. Because the records are files in the repository, they are reviewed and merged with the change they belong to, they survive a move to another forge, and they can be shown to an auditor without the forge.
