# Views: trace, coverage, diff, impact, export

For their users: `docs/commands.md`.

## The command line

%req[cli.commands]
skein shall be one program with a command as its first argument; without one, and for `help`, it prints what the commands and options are. A command it does not have is reported by name.

%req[cli.options]
An option skein does not have, an option that does not go with the command, and an option without the value it needs shall each be reported by name, and nothing done.

## Trace

%req[trace.item]
`skein trace` shall show one item: its type, category and status, its place, its fingerprint, its attributes, the item it is a part of and its own parts, the links from it and to it with their review states, the items its text refers to and that refer to it, its approvals, and the citations of it.

%req[trace.closure]
It shall show everything above the item (what its links lead to, through any number of links) and everything below it (what leads to it), each item once, nearest first, also when links form a loop.

%req[trace.json]
With `--json`, the same shall be given as JSON, with the item's text.

## Coverage

%req[coverage.expected]
`skein coverage` shall count, for each link type and citation set marked as expected and each item type it applies to, the items that have such a link to them or such a citation of them, in all and per category, and list the ones that have none. Removed items are not counted.

%req[coverage.parts]
An item with parts shall also count as covered when every one of its parts that the expectation applies to is covered, each itself or through its own parts. Removed parts do not count, and an item with no such part is covered only itself.

%req[coverage.profile]
With `--profile`, only the items of that profile shall be counted.

%req[coverage.reports]
Coverage shall report and not fail: its exit status is 0 whatever the numbers are.

## Changes

%req[diff.changes]
`skein diff` shall list the items added, removed and changed between a commit and the files as they are, or between two commits. An item is changed in its content when its fingerprint differs; a different status, links, attributes or verification method are named as such. An item given the status of a removed item is removed.

%req[diff.history]
The project at a commit shall be read from git with the code that reads the files as they are, without changing the working tree; a commit from before the project existed is an empty project, and a commit git does not know is refused.

%req[impact.reach]
`skein impact` shall list, for the items removed or changed in content: every item below them and every item whose text refers to them, the reviewed links to them that are now suspect, and the citations of them.

%req[diff.formats]
`diff` and `impact` shall give their result as text, as JSON, or as Markdown for a pull request.

## Export

%req[export.json]
`skein export` shall give the whole graph as one JSON document: the item types and link types, and every item as `trace` shows one.

%req[export.csv]
It shall give the items, the links and the citations each as CSV, one row each: the items with the item each is a part of, a column per attribute and their text, the links with their review states.

%req[export.profile]
With `--profile`, an export shall hold only the items of that profile, with their links and citations.
