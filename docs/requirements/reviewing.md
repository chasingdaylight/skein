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
`skein approve` shall record, for each named item, who approved it, on which day, and the fingerprint of the item at that moment. The name is the one given, or the username configured in git. The day is the one given, or today.

%req[approval.records]
The approvals shall be kept under `.skein/approvals/`, in files named in the same way as the review records, with one line per item and approver. A new approval by the same approver replaces the earlier record.

%req[approval.current]
An approval shall count as an approval of the current item only while the fingerprint of the item equals the one recorded. The record of an earlier version is kept, and is shown as an approval of an earlier version.

%req[approval.status]
An item type may name statuses that require an approval. An item with such a status and no approval of its current content shall be reported.

%req[citations.review]
A citation set can ask for reviews, `review = true` in its `[[citations]]` table, so that the citations of a rule by tests and code are held to the same care as a link of a reviewed type: `skein check` shall report a citation of an item whose citation was never reviewed, and one whose item has changed since (its fingerprint differs from the record). `skein review FILE...` (or `--all`) records the citations in those files as reviewed, and `skein clear ID...` those that name those items. The records are under `.skein/reviews/citations/`, one file for each citing file, one sorted line for each citation, written by Skein and committed with the change that was reviewed; a record of a citation that no longer exists is dropped when its file is next written. A citation set that does not ask for reviews is never reported. (#212.)

%req[approval.approvers]
An item type that has approvals shall be able to say who may approve, `approvers = ["name", ...]` in its `[approval]` table, or for each role, `[approval.approvers]` with a list per role (a role that is not one of the type's is a problem of the schema). An approval counts only when given by one of them, as `--by` or a reviewer's login names them: `skein check` reports an item that needs an approval and has one only by someone else, `skein approve` refuses to record one that would not count, and `skein approve --from-pull-request` records a reviewer's approval of an item of such a type in the role they may act in, or not at all, and says whose it left out. A type that names no approvers lets anyone approve, as before. Skein has no sign-in of its own, so the names are those the records carry; who may change the list is the project's review of `.skein/types/`. (#213.)

%req[approval.roles]
An item type may also name the roles that must each approve its items (`[approval] statuses = [...]`, `roles = [...]`). Its approvals are then given in a role, `skein approve ID --as ROLE`, which is recorded with them; an approval without a role, or in a role the type does not name, is refused. An item with a status that needs approval is approved only when every role has a current approval of it, and `check` names the roles still missing; `trace` shows each approval's role and the roles still to approve. Who may act in a role is not checked: the records are in git, with their commits.
