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
`skein lsp` shall serve the Language Server Protocol on standard input and output: it answers `initialize` with what it can do, refuses requests before that, answers a request it does not know with an error and no more, and ends with status 0 after `shutdown` and `exit`. The project is the one in the directory the editor has open.

%req[lsp.diagnostics]
The server shall publish the problems that `skein check` reports as diagnostics, each on its file and line, its warnings as warnings: when it starts, and whenever a document is opened or saved or the editor says files have changed. When a file that had problems has none, its diagnostics are published as empty. The project is read from the files, so a change counts once it is saved.

%req[lsp.definition]
On the ID of an item, wherever it is written (a reference, a link, a citation in code or tests, or plain text), "go to definition" shall lead to the marker or the file that declares the item. On a marker that names a part by a leading dot, it leads to that part.

%req[lsp.references]
"Find references" on an item shall list its declaration, when asked for, and every place that names it: references in the text of items and in narrative text, links, and citations.

%req[lsp.hover]
Hovering over the ID of an item shall show its ID, type, category and status, its text, and its parts. The position is taken in the text the editor shows, saved or not.

%req[lsp.completion]
The server shall complete what is being written where skein reads it: the item type after a `%` at the start of a paragraph or list entry; the ID in a reference; after the ID of a marker, the categories, statuses and attributes of its type and the link types it may have; the value of a key of a marker (the items a link may point to, the statuses, the verification methods, the values of an attribute); and the ID after a citation marker in code and tests. A completion replaces the word being written. Removed items are not offered, and the new ID of a marker is not completed.

%req[lsp.rename]
Renaming an item from the editor shall do what `skein move` does, and be refused with its reason when `skein move` would refuse. It is refused while an open document of the project has changes that are not saved, since the rename is made in the files.
