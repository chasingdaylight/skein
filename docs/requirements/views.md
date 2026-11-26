# Views: trace, coverage, diff, impact, export, render

The user documentation is in `docs/commands.md`.

## The command line

%req[cli.commands]
Skein shall be one program that takes a command as its first argument. Without a command, and for `help`, it prints the commands and options. An unknown command is reported by name.

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

%req[coverage.expected-of]
An expectation may apply to some of the items of its `to` types only: `expected = { where = { ATTRIBUTE = VALUE } }` to the items whose attribute has the value (one of several, given as an array; `verification`, `category` and `status` may be named too), and `expected = { profile = "P" }` to the items of a profile, which must exist. Coverage counts only the items it applies to; `expected = true` applies to all.

%req[coverage.profile]
With `--profile`, only the items of that profile shall be counted.

%req[coverage.reports]
Coverage shall report and not fail: the exit status is 0 whatever the numbers are.

%req[coverage.markdown]
With `--markdown`, `skein coverage` shall give the same counts as one Markdown table, followed for each expectation by the list of the items that are not covered, in a section that is folded until opened. It is meant for the summary of a CI job or a comment on a pull request.

## Changes

%req[diff.changes]
`skein diff` shall list the items added, removed and changed between a commit and the current files, or between two commits. The content of an item has changed when its fingerprint differs. A different status, different links, attributes or verification method are each named as that kind of change. An item that was given the status of a removed item is listed as removed.

%req[diff.history]
The project at a commit shall be read from git by the same code that reads the current files, without changing the working tree. A commit from before the project existed is an empty project, and a commit unknown to git is refused.

%req[impact.reach]
For the items removed or changed in content, `skein impact` shall list every item below them, every item whose text refers to them, the reviewed links to them that are now suspect, and their citations.

%req[diff.formats]
`diff` and `impact` shall give their result as text, as JSON, or as Markdown for a pull request.

## Markdown as HTML

Skein turns Markdown into HTML with code of its own, which nothing is fetched for. It covers what documents of requirements and specifications use, as GitHub shows it; it is not a complete CommonMark renderer.

%req[html.blocks]
Skein shall render the blocks it reads as HTML: paragraphs, block quotes (their content read as Markdown again), thematic breaks, and HTML blocks passed through as they are. Front matter is left out. A file with CRLF line ends gives the same HTML as with LF.

%req[html.headings]
A heading shall get an anchor as GitHub makes it: in lowercase, punctuation left out, spaces as hyphens; a second heading of the same name gets `-1`, a third `-2`. The first heading of level 1 gives the document its title.

%req[html.lists]
Lists shall be rendered ordered or unordered, an ordered one from its first number, with each entry read as Markdown of its own, so lists nest. In a list without blank lines between entries, an entry's first paragraph is not put in a paragraph element.

%req[html.code]
Fenced and indented code blocks shall be rendered with their lines as they are, escaped, and a fenced block's language given as the class `language-` and its name.

%req[html.tables]
Tables shall be rendered with their header, their rows, and the alignment of each column from its delimiter row. A `|` in a code span or after a backslash does not end a cell. Lines that start with `|` and have no delimiter row are a paragraph.

%req[html.inline]
Inline Markdown shall be rendered: emphasis and strong with `*` and `_` (not `_` inside a word), strikethrough with `~~`, code spans, links with an optional title, images, autolinks in angle brackets, bare `http://` and `https://` URLs, raw inline HTML passed through, backslash escapes, and hard line breaks. Text is escaped, and character references such as `&copy;` are kept. For a site, a relative link to a `.md` file can be made one to the `.html` file, its anchor kept.

## Baselines

%req[baseline.tag]
`skein baseline NAME [--message TEXT]` shall make an annotated git tag `NAME` of the commit checked out, whose message starts with `skein baseline NAME`, then gives the message, and then what the project held: its number of items and what `skein coverage` counts. The tag is made in the local repository only; Skein says how to share it. `skein diff` and `skein impact` take a baseline's name as they take any commit.

%req[baseline.refusals]
`skein baseline` shall refuse, and make no tag, when the project is not in a git repository, when the name cannot be a tag, when a tag of that name exists, when the project has changes that are not committed, and when `skein check` reports problems: a baseline is of a committed state without problems.

%req[baseline.list]
`skein baseline` without a name shall list the baselines, oldest first, with their dates: the tags whose message starts as a baseline's does. Other tags are not listed.

## Examples

%req[examples.command]
`skein examples --out DIR` shall write the code of each example that is not removed to a file of its own in `DIR`, named after its ID with the extension the example type gives for its language (else the language itself), and `examples.json`: for each, its ID, file, language, whether it must be accepted or rejected, the items it shows (its links of the type's link type, or all its links when the type gives none), its source file and line, and the messages it must give (`examples.messages`; none when the type names no `message`). Skein runs none of them.

## Export

%req[export.json]
`skein export` shall give the whole graph as one JSON document: the item types and link types, and every item as `trace` shows one.

%req[export.csv]
`skein export` shall also give the items, the links and the citations as CSV, one row each. An item row has the containing item, a column per attribute, and the text. A link row has its review state.

%req[export.profile]
With `--profile`, an export shall hold only the items of that profile, with their links and citations.

%req[export.reqif]
`skein export reqif` shall give the items as ReqIF 1.2 (OMG), for DOORS and other requirements tools: a spec object type per item type, with string attributes for the ID, the category, status and verification method where the type has them, and each declared attribute, and an XHTML attribute `ReqIF.Text` for the text (a paragraph to each block; the name DOORS and Jama Connect take for an object's text); a spec object per item; a spec relation type per link type and a spec relation per link between exported items; and a specification per document (an item file's directory, for items of their own), its items in order with their parts under them. Identifiers come from the IDs, so that the export of a later commit updates the same objects; `LAST-CHANGE` is the time of the last commit of the item's file, or of the last commit, or a fixed time outside a repository, so that the same files give the same bytes. (Issue #102.)

## Render

%req[render.markdown]
`skein render --out DIR` shall write every Markdown file of every source to `DIR`, under the path the file has in the project, as Markdown for a site generator. Text that is not a marker or a reference is written unchanged, byte for byte, including its line endings.

%req[render.markdown.markers]
In a rendered document, each marker shall be replaced by an anchor named after the ID of the item, followed by the ID as a link to that anchor and, when the marker gives them, the category and the status. A marker inside a code block is not an item and is left unchanged.

%req[render.markdown.references]
Each reference, in the text of an item or in narrative text, shall be replaced by a Markdown link to the item, showing the words the reference gives or else the ID. The link is the anchor alone for an item in the same document, and otherwise the relative path to the file of the item, with the anchor when that file is a document. A reference to an item of another repository links to it on that repository's site (`network.site`), and is its words without a link when the repository gives no site. A reference to an item that cannot be found, here or in another repository, is its words marked as unresolved: an HTML `span` of the class `skein-unresolved`, whose title names the reference, which the site shows in red.

%req[render.markdown.item-files]
A rendered item file shall start with YAML front matter that gives the ID as the title, in place of the TOML front matter, followed by the category and status when the item has them, and the text. A file in a source of item files that is not an item is written unchanged.

%req[render.editions]
With `--editions`, `skein render` shall also render each baseline, from the files of its commit, into `DIR/editions/NAME/` in the same format, without results, and write a page there (`index.md`, or `index.html` for the HTML formats) that lists the files as they are now and then the baselines, newest first, with their dates and links; a baseline that cannot be rendered is said so and left out. (Issue #103; design section 8.)

%req[render.markdown.output]
`skein render` shall create `DIR` when it does not exist, shall not change any file of the project, and shall say how many files or pages it wrote. Without `--out` it is refused. The formats are `markdown` (the default) and `html`.

%req[render.site.pages]
`skein render --format html --out DIR` shall write each document and item file of every source as an HTML page under its own path, with `.html` for `.md`: its markers and references rendered as `render.markdown` gives them, then as HTML, links to `.md` files made links to the pages, the first heading of level 1 (or the ID of an item file) as its title, and a navigation of all the pages. The images and other files of the sources (`.png`, `.svg`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.pdf`, `.css`) are copied beside them.

%req[render.site.index]
The site shall have a front page that lists its pages with their titles and files, and a page of all the items with, for each, its type, category and status, a link to where it is, the items that link to it with the link type, the items whose text refers to it, and how often narrative text mentions it.

%req[render.site.relative]
Every link and every reference to a file in the site shall be relative, and nothing shall be loaded from another address: the styles are in each page. So the site can be served under any address, or opened from disk.

%req[render.generated]
A fenced code block of the language `skein` in a document shall be a request for a page that Skein generates from the graph: `skein render` puts the page in its place, as Markdown and as HTML alike, and its links lead to the items from the page they are on. A request Skein cannot read is replaced by a note that says what is wrong. Removed items are never listed.

%req[render.generated.list]
`list [TYPE...] [category=C] [status=S] [profile=P] [ATTRIBUTE=V]` shall give a table of the items that pass every condition given, in the order of the items: each with a link to it, its category, its status and the first paragraph of its text. A glossary is the list of the type of terms. With `columns=C,...`, the columns are those given instead, as a matrix's are: a table of models with their assessed factors, say.

%req[render.generated.matrix]
`matrix LINKTYPE [conditions]` shall give a table of the items that the link type may point to, each with the items that link to it by that type, the ones without any shown as such, and a count of how many have one.

%req[render.generated.matrix-columns]
`matrix LINKTYPE [conditions] columns=C,... from.columns=C,...` shall give, after the item, the columns `columns` of the item pointed to and, after the items that link to it, the columns `from.columns` of each, one row per item that links to it when those are asked for. A column is `id`, `type`, `category`, `status`, `text` (the first paragraph) or an attribute; each value that is the ID of an item is a link to it, and the values of an attribute with several are joined by commas.

%req[render.generated.coverage]
`coverage [profile=P]` shall give what `skein coverage` counts, as a table, with links to the items that are not covered.

%req[render.burn]
`burndown MILESTONE [weight] [from=DATE] [to=DATE]` and `burnup ...` shall give a milestone's charts, as GitLab draws them, as `mermaid` blocks: over its days (from the first start of its work, else `from`, to its finish, else `to`) up to today, the burndown shows what remains beside a straight guideline from the starting total to none on the last day; the burnup shows the scope and what is done. Under each, a table of the days with the scope, what is done and what remains. A milestone whose days are not known is said so.

%req[render.board]
`board [TYPE...] [conditions] [by=status|assignee|milestone]` shall give a board of the work items that pass the conditions, as a table with a column for each status (the work types' statuses in their order, the tombstone left out), assignee or milestone, headed with how many cards it has, and a card for each item in its column: its ID, linked, and the first line of its text. (Design, section 10.3.)

%req[render.roadmap]
`roadmap [MILESTONE...]` shall give the milestones (those named, else every work item that work names as its milestone), in the order of their finish: each with its start (its own, else the first start of its work), its finish, how many of its work items are done of how many, as a share and a bar, and its work items, linked. (Design, section 10.3.)

%req[render.gantt]
`gantt [TYPE...] [conditions] [by=parent|assignee] [baseline=NAME]` shall give the schedule of the work items that pass the conditions as a Gantt chart, a `mermaid` block drawn as `render.mermaid` says, as `skein schedule` computes it: a bar for each scheduled item, marked critical on the critical path, a milestone for work of no duration, the days that are not working days left out, in a section for each item with parts (with its parts) or, `by=assignee`, for each assignee; with `baseline=NAME`, each item's bar in the schedule stored at that baseline (a tag) drawn under its bar now, to show slippage. Under the chart, a table of each item with its start, finish, slack and predecessors, linked, and the items that cannot be scheduled. (Design, section 10.3.)

%req[control.maturity]
A controlled document's front matter may name the item it is (`item`) and the maturity it is at (`maturity`). With `[maturity]` in the configuration, giving the maturities lowest first (`order`) and the milestone the project is at (`milestone`), `skein check` shall warn of a document below the value its item has for the attribute the milestone names, of a document that gives no maturity or one outside the order, and of one that names no item there is; a value outside the order (complete, per schedule) expects nothing.

%req[control.gates]
With a gate for the milestone the project is at (`[maturity.gates.NAME]`), `skein check` shall warn when more of the items than `tbd` percent are undecided (their status is one of `[maturity] tbd`, default `tbd` and `tbr`), and when `volatility` percent or more of them were added, changed (in content) or removed since the last baseline; the items counted are those of the types that have one of those statuses, removed ones left out. `skein coverage` shall give the numbers against the gate. A share is 0 to 100. (Issue #188; the NASA Software Engineering Handbook's review checklists, topic 7.09.)

%req[render.control]
A document that gives `document` (its identifier) and `revision` in TOML front matter shall be rendered with, under its first heading of level 1, a table of its identifier, its revision and its last change (the date, the author and the commit, linked on the forge when the project names one), and at its end a change record: each baseline in which its items changed, oldest first, with its date, the message given to `skein baseline`, and how many of its items were added, changed and removed since the baseline before. A rendered item file gives the date, author and commit of its last change in its front matter. A generated `documents` page lists the controlled documents with their identifier, title, revision and last change. All of it is read from git; outside a git repository there is none.

%req[render.mermaid]
A fenced code block of the language `mermaid` shall be drawn as a diagram in the pages of `--format html` and `--format document`, by mermaid.js built into Skein (`vendor/mermaid`): a site has one copy of it, at its root, which only the pages with a diagram load; a standalone document with a diagram has it inside. Pages without a diagram are as they were. Markdown output leaves the block as it is, for a site generator to draw.

%req[render.documents]
`skein render --format document --out DIR` shall write each document and item file as one HTML file of its own, under its own path: the same page as in the site, without the navigation, with its images put in it as `data:` addresses, and with a style sheet for printing. Nothing else is written.

%req[render.profiles]
With `--profile NAME`, `skein render` shall render only the items of that profile, in every format. An item outside it is left out with its lines and its parts; a part is in a profile only when the item it belongs to is. A reference to an item left out is shown as its words, without a link; an item file outside it is not written; generated pages and the page of all items list only the items of the profile. A profile that does not exist is refused.

%req[render.order]
A source of item files with `order_by = "ATTRIBUTE"` shall have its files rendered in the order of that attribute's values, compared as dotted numbers part by part (`2.9` before `2.10`), and its files whose item has no value after them, by path. Without it, files are rendered by path.
