# Checking

What `skein check` reports. For its users: `docs/writing-items.md` and `docs/commands.md`.

%req[check.report]
A problem shall be reported on one line, as `file:line:column: error: message`, with the file from the project's root; the line and column are left out when the problem is not at one place. Problems are in the order of their files and places.

%req[check.exit-status]
A command shall end with status 0 when it did what it was asked, 1 when the project has problems, and 2 when it was not used as it must be or there is no project. With status 0 its answer is on standard output; otherwise what is wrong is on standard error.

%req[check.schema-first]
When the configuration or the schema has problems, the items shall not be read: only those problems are reported.

%req[check.ids]
An ID used by two items shall be reported at the second, with the place of the first. An ID that is not spelled as its item type spells IDs is reported.

%req[check.removed-ids]
A removed item's ID shall count as used: another item with it is reported like any ID used twice.

%req[check.type-rules]
An item shall be reported when its type does not exist, when its category, status or verification method is not one its type has, and when its type has categories and it has none.

%req[check.attributes]
An attribute shall be reported when its item's type does not declare it, when its value is not of its kind or not one of its values, and when it is required and missing.

%req[check.links]
A link shall be reported when its target does not exist or is removed, when its target or its own item is of a type the link type does not allow, and when it points to its own item. An item without a link its type must have is reported.

%req[check.references]
A reference in an item's text to an item that does not exist or is removed shall be reported, at its line and column.

%req[check.citations]
A citation of an item that does not exist, is removed, or is of a type its citation set may not name shall be reported, at its file, line and column.

%req[check.removed-exempt]
A removed item shall not be asked for a category, required attributes, required links or text.

%req[check.other-repositories]
A link, reference or citation whose target has a colon (`name:id`) names an item of another repository; until repositories are linked, it shall be accepted and not checked.
