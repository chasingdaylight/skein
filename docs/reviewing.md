# Fingerprints, reviews and suspect links

When a requirement changes, what was derived from it, and what tests it, may no longer be right. skein finds those places: a link can record what its target said when the link was last reviewed, and `skein check` reports the link as suspect once the target says something else.

## Fingerprints

Every item has a fingerprint: a hash of what it says.

| Part of it | Not part of it |
| --- | --- |
| The item's text | Its status |
| Its type and its category | Its links |
| The attributes its type marks `normative = true` | Its other attributes |
| | Its ID and where it is written |

The text is taken without its layout: runs of spaces and line ends count as one space, so rewrapping a paragraph, changing line endings or re-indenting a list changes nothing. Inside code blocks the lines are kept, because there they can matter.

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
