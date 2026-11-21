# Fingerprints, reviews and approvals

For their users: `docs/reviewing.md`.

## Fingerprints

%req[fingerprint.content]
An item's fingerprint shall be a hash of its type, its category, the attributes its type marks as part of what it says, and its text. Its status, its links, its other attributes, its ID and its place are not part of it.

%req[fingerprint.parts]
The fingerprint of an item with parts shall also be over the names and the fingerprints of its parts, in their order, so that a change to what a part says, or to its name, changes its whole's fingerprint, and that of every whole above it. A part's name is what follows its whole's ID when its ID continues that one, and else its ID, so that renaming the whole alone changes nothing. The statuses of the parts are not part of it.

%req[fingerprint.layout]
A change of layout alone shall not change a fingerprint: line ends, runs of spaces, and where lines are wrapped. Inside a code block the lines and their indentation are part of what is said; only spaces at their ends are not.

## Reviewed links

%req[review.per-link-type]
Reviews shall be asked for per link type. A link of a type that does not ask for them is never reported for want of one.

%req[review.state]
A link of a reviewed type shall be reported when it was never reviewed, and when its target's fingerprint is no longer the one recorded at its review.

%req[review.commands]
`skein review` shall record, for the links of the items named, their targets' fingerprints as they are now; `skein clear` the same for the links to the items named; each also for every link, with `--all`. An ID that names no item is refused.

%req[review.records]
The review records shall be kept under `.skein/reviews/`, never in the items or beside the documents: one file per document, and one per directory of item files, with one sorted line per link, in TOML. A file left without records is removed.

%req[review.records.stale]
When a record file is written, records of links that no longer exist shall be left out of it.

## Approvals

%req[approval.record]
`skein approve` shall record, for each item named, who approved it, on which day, and its fingerprint at that moment. The name is the one given, or the one git has for the user; the day is the one given, or today.

%req[approval.records]
The approvals shall be kept under `.skein/approvals/`, in files named as the review records are, with one line per item and approver. Approving again replaces that approver's earlier record.

%req[approval.current]
An approval shall count as of the item as it is only while the item's fingerprint is the one recorded. The record of an earlier version stays, and is shown as such.

%req[approval.status]
An item type may name statuses that need an approval. An item with such a status and no approval of what it says now shall be reported.
