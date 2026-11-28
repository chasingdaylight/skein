# Editing and editors

Commands that change the files of a project, and the language server for editors. The user documentation is in `docs/commands.md`.

## Renaming an ID

%req[move.everywhere]
`skein move OLD NEW` shall give the item `OLD` the ID `NEW` everywhere the old ID is used: in its marker or front matter, in every reference in the text of an item and in narrative text, in every link, and in every citation in code, in tests and in `.skein-cites` files. Only whole IDs are replaced, and only on the lines that name them: an ID inside a longer one, an ID of another repository, and the same letters elsewhere in a file are left unchanged.

%req[move.parts]
The parts of the item whose IDs continue its ID shall follow it, at any depth: `lex.keywords.as` becomes `lex.kw.as` when `lex.keywords` becomes `lex.kw`. A part named by a leading dot needs no change to its marker. When the item moved is itself named by a leading dot, its marker keeps the dot if the new ID still continues the ID of the containing item, and otherwise gives the new ID in full. A part with an ID of its own is not renamed.

%req[move.item-files]
An item file whose name is its ID shall be renamed to the new ID.

%req[move.records]
A rename is not a change to the content of anything. The review and approval records shall be written with the new IDs, and every review and every approval that was current before the rename shall be current after it, also where the rename changed a fingerprint: of an item whose text refers to the renamed item, or of an item that contains a renamed part.

%req[move.refusals]
`skein move` shall refuse, and change nothing, when there is no item with the old ID, when the new ID is not spelled as the IDs of the item's type are, when the new ID or the new ID of a part is taken by another item, and when the old and the new ID are the same.

%req[move.aliases]
`skein move` shall keep the old ID, and the old IDs of the parts that follow it, as aliases of the items (`items.aliases`), in their markers or front matter: with `--alias`, and by default when the project declares an `id`, since other projects can then cite it; with `--no-alias`, or without an `id`, not. A new ID that is a former ID of an item is refused, so that it is taken out of the aliases first.

## Starting an item

%req[new.numbered]
`skein new TYPE` shall give a new item of a numbered type the next free number: one more than the highest number of an item of that type, removed items included, with at least the type's number of digits. A name in the number's place is no number.

%req[new.named]
`skein new TYPE ID` shall start an item with the ID given, for a type of any ID scheme; a type whose IDs are joined by dots needs it.

%req[new.file]
Where the type has one source of item files, or `--to DIR` names one, the new item shall be written there as `ID.md`, with front matter that gives its ID, and its type when the source does not give it, and no text yet. A file that is there already is never written over. The path of the file is printed.

%req[new.marker]
Where the type has no source of item files, the marker to start a paragraph or list entry with shall be printed, and nothing written.

%req[new.refusals]
`skein new` shall refuse, and write nothing, when the type does not exist, when the ID is taken (also by a removed item) or is not spelled as the type's IDs are, when `--to` names no source of item files, and when the type has more than one source of item files and `--to` names none of them.

## Adding a link

%req[link.add]
`skein link FROM TYPE TO` shall add a link of the type `TYPE` from the item `FROM` to the item `TO`, and change nothing else in the file.

%req[link.marker]
For an item in a document, the link shall be added to its marker: to the values of the key when the marker has that key, else as a new `key=value` before the closing bracket.

%req[link.front-matter]
For an item file, the link shall be added to its front matter: to the key's array or string when it is written on one line, else as a new key right after the ID, where it cannot fall into a table. Line endings are kept. A key written another way is not changed, and the command says to add the link by hand.

%req[link.refusals]
`skein link` shall refuse, and write nothing, what `skein check` would report: an item or link type that does not exist, a link type the item's type cannot have, a target of a type the link cannot point to, a removed target, a link to the item itself, and a link that is there already. A target of another repository (`name:id`) is accepted unchecked, as `check` accepts it.

## The language server

%req[lsp.lifecycle]
`skein lsp` shall serve the Language Server Protocol on standard input and output: it answers `initialize` with what it can do, refuses requests before that, answers a request it does not know with an error and no more, and ends with status 0 after `shutdown` and `exit`. The projects it serves are those of %[lsp.projects].

%req[lsp.projects]
The server shall serve every project of the editor's folders: the project a folder is in, and the projects inside it, four levels down (not entering directories whose names start with a dot, nor build outputs); and the project of each document opened, the nearest `.skein/` above it, from then on. A request about a document is about the document's project; one that names no document is about the project it names (`project`, the URI of its root), else the first project found. `skein/projects` shall give each project's name and the URI of its root. When the editor adds or removes folders, the projects are found again. (emanspeaks, 2026-11-27, #307.)

%req[lsp.diagnostics]
The server shall publish the problems that `skein check` reports as diagnostics, for every project it serves, each on its file and line, its warnings as warnings: when it starts, and whenever a document is opened or saved or the editor says files have changed. When a file that had problems has none, its diagnostics are published as empty. The project is read from the files, so a change counts once it is saved.

%req[lsp.definition]
On the ID of an item, wherever it is written (a reference, a link, a citation in code or tests, or plain text), "go to definition" shall lead to the marker or the file that declares the item. On a marker that names a part by a leading dot, it leads to that part. On `name:id`, it leads into the checkout of that repository, when it has one on disk.

%req[lsp.references]
"Find references" on an item shall list its declaration, when asked for, and every place that names it: references in the text of items and in narrative text, links, and citations.

%req[lsp.hover]
Hovering over the ID of an item shall show its ID, type, category and status, its text, and its parts. The position is taken in the text the editor shows, saved or not.

%req[lsp.completion]
The server shall complete what is being written where Skein reads it: the item type after a `%` at the start of a paragraph or list entry; the ID in a reference; after the ID of a marker, the categories, statuses and attributes of its type and the link types it may have; the value of a key of a marker (the items a link may point to, the statuses, the verification methods, the values of an attribute); and the ID after a citation marker in code and tests. A completion replaces the word being written. Removed items are not offered, and the new ID of a marker is not completed.

%req[lsp.rename]
Renaming an item from the editor shall do what `skein move` does, and be refused with its reason when `skein move` would refuse. It is refused while an open document of the project has changes that are not saved, since the rename is made in the files.

%req[lsp.lens]
Above each item declared in a file, the server shall give a code lens "Trace", which opens the item's trace, and, when the item has links or is linked to, one with those links, which opens a choice of the items they lead to.

%req[lsp.fixes]
A problem that names what would mend it shall be offered as a quick fix that writes that word in place of the other: the ID an item has now for a former one, and, for a word that is misspelled, the one it is closest to (within two edits, and closer than any other) among the IDs of the items, the categories and statuses of the item's type, its attributes and link types, and its verification methods.

%req[lsp.items]
The request `skein/items` shall give every item of the project with its type, category, status, file, line, the item it is a part of, the first line of its text, its source and whether it is removed, and the project's name and sources; `skein/itemAt` gives the ID of the item under a position.

%req[lsp.views]
The request `skein/trace` shall give the trace of an item, found also by a former ID, as HTML: what `skein trace` prints, with each item and place a link that the editor opens (`skein:item/ID`, `skein:file/PATH#LINE`). `skein/coverage` shall give the coverage page that a document's `coverage` request renders, as HTML with the same links, and how many items of all that are expected are covered.

%req[lsp.planning]
The request `skein/schedule` shall give the work items as `skein schedule` schedules them, with their status, mode, slack, predecessors, parents and assignees, the statuses of the work types, and the calendar. `skein/plan` (`{ "id": ID }` with `start`, `finish` or `status`) shall write the change into the item's marker or front matter: a start moves the item, and makes a float item fixed; a finish sets its duration in working days (and its finish, where one is written); a status replaces its status. Then the stored schedule is written again, as `skein schedule` writes it. It is refused, with its reason, for an item that is no work or is in a read-only source, a status its type does not have, and while the item's file has changes that the editor has not saved.

%req[lsp.preview]
The request `skein/render` (`{ "uri": URI }`) shall give a file of the project's sources as `skein render` writes it (markers as anchors and IDs, references as links, unresolved references marked, generated pages in place), with the text on disk it was rendered from; nothing for a file that is in no source.

%req[lsp.graph]
The request `skein/graph` shall give the network of items: each item that is not removed with its type, status, first line of text, place, source and the profiles it is in; each link with its type and, where links of its type are reviewed, whether it is reviewed, suspect or never reviewed, a link by a former ID leading to the item now; an item of another repository that a link points to as a node of its own; and the project's item types, link types, profiles and sources.

%req[lsp.forms]
The request `skein/form` (`{ "id": ID }` or `{ "type": TYPE }`) shall give what an item form shows: the item's category, status, verification method, attributes, links and text, and what its type allows (categories, statuses, attributes with their kinds and values, the link types it may have with the items each may point to, whether its IDs are numbered), and where a new item goes (a source of item files, or the project's documents). `skein/saveItem` shall write a form: each value that differs from the item's into its marker or front matter, an empty one taken out; a new item started as `skein new` starts it, in a file of its own or at the end of the document chosen, with its text. It refuses, with the reason, a category, status, verification method, attribute or link type the type does not have, a link to an item there is not, and an item in a read-only source.

## The VS Code extension

%req[edit.vscode]
A VS Code extension on the language server shall be Skein's graphical interface, with the item tree, trace and coverage views, forms for items, and interactive planning views. (Design, section 9.)

%req[vscode.server]
The VS Code extension shall start `skein lsp` itself, the program it carries or the one `skein.path` names, and restart it when that setting changes or on the command; diagnostics, go to definition, references, hover, completion and rename then work with nothing to configure.

%req[vscode.projects]
The extension shall work in a workspace any of whose folders is in a project or has one inside it, not only one whose first folder is a project. Where the workspace has several projects, the views, the status bar and the commands are about the project of the active editor's file, else the one last chosen with **Skein: Choose Project...** (the command palette, the Items view's title bar), and the Items view names it. (emanspeaks, 2026-11-27, #307.)

%req[vscode.tree]
The extension shall show the items in a tree in the sidebar, by source and file, with each item's ID, type and status and its parts under it; choosing an item opens it at its marker. The tree is read again when a file of the project is saved, created or deleted.

%req[vscode.views]
"Trace" on an item (a code lens, the editor's or the tree's context menu, or the command palette) shall open its trace in a view; "Show Coverage" opens the coverage page. The views take their colors and fonts from VS Code's theme, and their links open the items and places in the editor.

%req[vscode.status]
The status bar shall show how much of what is expected is covered, and open the coverage view when it is clicked.

%req[vscode.planning]
"Show Plan" shall open the planning view: a Gantt chart of the schedule, with the critical path, the links between items, the milestones and the days off, whose bars are dragged to move an item or, by their right end, to change its length; and a board with a column for each status, whose cards are dragged from one to another. Each drag is written into the item's file (`lsp.planning`), and the view shows the schedule that follows; a change that is refused is said, and the view shows what is there. (Design, sections 9 and 10.3.)

%req[vscode.preview]
VS Code's Markdown preview shall show a saved document of the project as `skein render` writes it, from `skein/render`: markers as the item's anchor and ID with its category and status, references as links to the items (which open their files), unresolved references marked in the theme's error color, and generated pages in place. While a document has changes that are not saved, the preview shows it as written; it is rendered again when it is saved, and when the project changes. (emanspeaks, 2026-11-22, #158.)

%req[vscode.graph]
"Show Graph" shall open a view of the network of items, modeled on the Git Graph extension (#130): items in layers, each above the items that link to it, colored by type in the theme's colors, suspect and never-reviewed links drawn as such, items of other repositories set apart; panned by dragging and zoomed with the wheel or a touchpad's pinch, and, without either, with buttons and keys to zoom in and out, fit the graph to the panel and show it at its size; a search that brings the items it finds into view and dims the rest; filters by item type, link type, profile, source and other repositories, kept between sessions; a chosen item's trace beside the graph, whose links choose other items; and, there and on a node's context menu, the actions on an item: open it, trace it, copy its ID, review its links, approve it.

%req[vscode.forms]
"New Item" (the command palette, the Items view's title bar) and "Edit Item" (the editor's and the tree's context menus) shall open a form of an item's type, ID (for a new one; empty for the next number of a numbered type), category, status, verification method, attributes (a choice where the attribute has values, a number, a date) and links (with the items they may point to offered), and, for a new item, the document it goes in and its text. A required attribute left empty, and a new item with no ID or place, are said before anything is sent; saving writes the form (`lsp.forms`), says why when it is refused, and opens the item.

%req[vscode.commands]
Every action of the extension shall be a command in the command palette, and on the context menus where it belongs; its settings are under `skein.*`, each with a description.
