# Checking

What `skein check` reports. The user documentation is in `docs/writing-items.md` and `docs/commands.md`.

%req[check.report]
A problem shall be reported on one line, as `file:line:column: error: message`, with the file path relative to the project root. The line and column are left out when the problem has no single location. Problems are ordered by file and location.

%req[check.exit-status]
A command shall end with status 0 when it did what was asked, 1 when the project has problems, and 2 when it was used incorrectly or there is no project. With status 0 the result is on standard output; otherwise the problem is described on standard error.

%req[check.schema-first]
When the configuration or the schema has problems, the items shall not be read: only those problems are reported.

%req[check.ids]
An ID used by two items shall be reported at the second item, with the location of the first. An ID that does not follow the ID scheme of its item type is reported.

%req[check.removed-ids]
The ID of a removed item shall still count as used: another item with the same ID is reported like any duplicate ID.

%req[check.type-rules]
An item shall be reported when its item type does not exist, when its category, status or verification method is not one the item type declares, and when the item type has categories and the item has none.

%req[check.attributes]
An attribute shall be reported when the item type does not declare it, when its value is of the wrong kind or is not one of the allowed values, and when it is required and missing.

%req[check.links]
A link shall be reported when its target does not exist or is removed, when the link type does not allow the item type of its target or of the item it starts at, and when it points to the item it starts at. An item without a link that its item type requires is reported.

%req[check.references]
A reference to an item that does not exist or is removed shall be reported at its line and column, whether it is in the text of an item or in narrative text.

%req[check.citations]
A citation of an item that does not exist, is removed, or has an item type the citation set may not name shall be reported at its file, line and column.

%req[check.removed-exempt]
A removed item shall not be required to have a category, required attributes, required links or text.

%req[check.other-repositories]
A link, reference or citation whose target has a colon (`name:id`) names an item of another repository, and shall be checked against that repository's items in the state read (`network.states`): a repository that is not declared, an item it does not have, a removed item, and an item of a type the link type or citation set may not point to are reported. When the repository's items could not be read, its targets are not checked, and that is a warning.

%req[check.warnings]
A warning shall say what could not be checked. It is shown with the problems, as `warning:` where they have `error:`, and counted apart from them; warnings alone do not fail a check.
