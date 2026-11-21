# Fingerprints, reviews and approvals

The user documentation is in `docs/reviewing.md`.

## Fingerprints

%req[fingerprint.content]
The fingerprint of an item shall be a hash of its item type, its category, its normative attributes (those the item type marks as part of the content of an item), and its text. The status, the links, the other attributes, the ID and the location of the item are not part of the fingerprint.

%req[fingerprint.parts]
The fingerprint of an item with parts shall also cover the name and the fingerprint of each part, in order. A change to the content of a part, or to its name, therefore changes the fingerprint of the containing item and of every item that contains that one. The name of a part is the remainder of its ID after the ID of the containing item when the ID of the part extends that ID (`.as`), and otherwise its full ID, so renaming only the containing item changes no fingerprint. The statuses of the parts are not part of the fingerprint.

%req[fingerprint.layout]
A change of layout alone shall not change a fingerprint: line endings, runs of spaces, and where lines are wrapped. Inside a code block, the lines and their indentation are part of the content; only trailing spaces are not.

## Reviewed links

%req[review.per-link-type]
Whether links are reviewed shall be set per link type. A link of a type that is not reviewed is never reported as lacking a review.

%req[review.state]
A link of a reviewed type shall be reported when it was never reviewed, and when the fingerprint of its target is no longer the one recorded at the review.

%req[review.commands]
`skein review` shall record the current fingerprint of the target of each link of the named items. `skein clear` shall do the same for each link that points to the named items. With `--all`, each does so for every link. An ID that does not name an item is refused.

%req[review.records]
The review records shall be kept under `.skein/reviews/`, never in the items or beside the documents. There is one file per document and one per directory of item files, in TOML, with one line per link, sorted. A file with no records left is removed.

%req[review.records.stale]
When a record file is written, the records of links that no longer exist shall be left out.

## Approvals

%req[approval.record]
`skein approve` shall record, for each named item, who approved it, on which day, and the fingerprint of the item at that moment. The name is the one given, or the user name configured in git. The day is the one given, or today.

%req[approval.records]
The approvals shall be kept under `.skein/approvals/`, in files named in the same way as the review records, with one line per item and approver. A new approval by the same approver replaces the earlier record.

%req[approval.current]
An approval shall count as an approval of the current item only while the fingerprint of the item equals the one recorded. The record of an earlier version is kept, and is shown as an approval of an earlier version.

%req[approval.status]
An item type may name statuses that require an approval. An item with such a status and no approval of its current content shall be reported.
