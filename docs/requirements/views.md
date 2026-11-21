# Views: trace, coverage, diff, impact, export

The user documentation is in `docs/commands.md`.

## The command line

%req[cli.commands]
skein shall be one program that takes a command as its first argument. Without a command, and for `help`, it prints the commands and options. An unknown command is reported by name.

%req[cli.options]
An unknown option, an option that does not belong to the command, and an option that is missing its value shall each be reported by name, and the command shall do nothing.

## Trace

%req[trace.item]
`skein trace` shall show one item: its type, category and status, its location, its fingerprint, its attributes, the item that contains it and its own parts, the links from it and to it with their review states, the items its text refers to, the items whose text refers to it, the places in narrative text that refer to it, its approvals, and its citations.

%req[trace.closure]
`skein trace` shall also show everything above the item (the items its links lead to, through any number of links) and everything below it (the items that lead to it), each item once, nearest first, including when links form a loop.

%req[trace.json]
With `--json`, the same information shall be given as JSON, including the text of the item.

## Coverage

%req[coverage.expected]
For each link type and citation set marked as expected, and each item type it applies to, `skein coverage` shall count the items that have such a link pointing to them or such a citation, in total and per category, and list the items that have none. Removed items are not counted.

%req[coverage.parts]
An item with parts shall also count as covered when every part that the expectation applies to is covered. A part is covered either directly or, in turn, through its own parts. Removed parts are not counted. An item with no part that the expectation applies to is covered only by a link or citation of its own.

%req[coverage.profile]
With `--profile`, only the items of that profile shall be counted.

%req[coverage.reports]
Coverage shall report and not fail: the exit status is 0 whatever the numbers are.

## Changes

%req[diff.changes]
`skein diff` shall list the items added, removed and changed between a commit and the current files, or between two commits. The content of an item has changed when its fingerprint differs. A different status, different links, attributes or verification method are each named as that kind of change. An item that was given the status of a removed item is listed as removed.

%req[diff.history]
The project at a commit shall be read from git by the same code that reads the current files, without changing the working tree. A commit from before the project existed is an empty project, and a commit unknown to git is refused.

%req[impact.reach]
For the items removed or changed in content, `skein impact` shall list every item below them, every item whose text refers to them, the reviewed links to them that are now suspect, and their citations.

%req[diff.formats]
`diff` and `impact` shall give their result as text, as JSON, or as Markdown for a pull request.

## Export

%req[export.json]
`skein export` shall give the whole graph as one JSON document: the item types and link types, and every item as `trace` shows one.

%req[export.csv]
`skein export` shall also give the items, the links and the citations as CSV, one row each. An item row has the containing item, a column per attribute, and the text. A link row has its review state.

%req[export.profile]
With `--profile`, an export shall hold only the items of that profile, with their links and citations.
