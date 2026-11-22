# Editing

Commands that change a project's files. The user documentation is in `docs/commands.md`.

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
