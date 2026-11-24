# Items, references and citations

The user documentation is in `docs/writing-items.md`.

## Reading Markdown

%req[markdown.blocks]
Skein shall read the block structure of a Markdown file: headings, paragraphs, lists (including lists with blank lines between entries), fenced and indented code, block quotes, tables, HTML blocks and thematic breaks, each with its first and last line. The content of a code block is never read as anything else.

%req[markdown.line-ends]
A file with CRLF line ends shall give the same blocks, the same items and the same fingerprints as the same file with LF line ends.

%req[markdown.yaml-front-matter]
YAML between `---` lines at the top of a file, as site generators and other tools write it, shall be skipped: frontmatter is not an item and does not contain items.

## Items in documents

%req[items.marker]
In a document, a marker at the start of a paragraph or of a list entry shall make that paragraph or entry an item. A marker is a percent sign, an item type, and in brackets the ID and optionally more words, as in `%rule[lex.comment syntax]`.

%req[items.marker.inline]
The text of an item shall follow the marker on the same line, or start on the next line.

%req[items.list-entries]
An entry of a list, at any depth, shall be an item when it starts with a marker.

%req[items.marker.bold]
A marker may be wrapped in bold, `**%rule[lex.comment syntax]** Text.`, so that it stands out where Skein does not render the document; that is never required (emanspeaks, 2026-11-22, #163). `**` before the marker and right after its closing bracket shall be part of the marker, not of the item's text; `**` before the marker that is closed further on, in bold that goes on into the text (`**%rule[a] Text.**`), shall be the text's. The rendered marker is bold once: in place of the writer's `**` around it, and without bold of its own inside the writer's bold.

%req[items.marker.types-only]
A marker shall be recognized only at the start of a paragraph or of a list entry, as a percent sign, a lowercase name and an opening bracket. The same characters elsewhere in a line, and anything in a code block, are text. A marker that names an item type the project does not have is reported.

%req[items.marker.words]
After the ID, a bare word shall be read as a category if the item type declares it as one, and otherwise as a status if the item type declares it as one; a marker has at most one of each, and a word that is neither is reported. A word of the form `key=value` gives the status, the verification method, links (when the key is a link type) or an attribute. Several values are separated by commas; a value in double quotes may hold spaces, and a closing bracket.

%req[items.marker.repeated]
A key that takes several values (a link type, `aliases`) may be given more than once in a marker: `shows=a shows=b` is `shows=a,b`. A key that takes one value, given twice, is reported.

## Tested examples

%req[examples.marked]
An item type with an `[example]` table in its file shall be one of tested examples. A fenced code block whose opening line has, after the language, a marker of such a type (```` ```cesium %example[ID words] ````, or a bare `%example`) is an item of it, whose text is the code block. A marker of any other type there is reported.

%req[examples.parts]
An example inside the text of an item shall be a part of it: with a leading-dot ID it is named within the item, and without an ID it is numbered in the item, `ID.example-1` and on. When the example type gives a link type (`link`), the part has a link of that type to the item, unless it gives one itself. An example outside an item needs an ID. An example with the category the type gives as `rejects` must be rejected; one without a category must be accepted, so an example type requires none.

%req[examples.coverage]
The links of examples, given or added for a part, shall count for coverage as any links do, so that `skein coverage` counts the items that have an example.

%req[items.marker.mistakes]
A marker that is not closed, has no ID, or has words that cannot be read as a category, a status or `key=value` shall be reported with its file, line and column, and shall not create an item.

%req[items.text-extent]
The text of an item shall be the rest of the block the marker is in (or, when the marker is alone on its line, the block after it), together with the lists, code blocks, tables and quotes that follow that block directly. A paragraph after that is not part of the item. A marker with no text is reported.

%req[items.parts]
When a list is in the text of an item, an entry of that list that starts with a marker shall be a part of that item. A part is an item in its own right. It records the item that contains it, and the containing item records its parts in order. Parts may have parts. In the order of items, an item comes before its parts.

%req[items.parts.names]
When the ID in the marker of a part starts with a dot, the ID of the part shall be the ID of the containing item followed by what the marker gives: `.as` inside `lex.keywords` is `lex.keywords.as`. An ID without a leading dot is used as written. A leading dot is reported when the item is not a part of another item, and when the item type of the part or of the containing item does not use IDs joined by dots.

%req[items.parts.text]
The text of a part shall belong to the part only, and not to the containing item. The own text of the containing item is its text without its parts: in a list with parts, only the entries that do not start with a marker.

%req[items.removed]
A marker with the status that the item type uses for removed items shall be an item without text: the marker alone.

%req[items.aliases]
An item shall be able to carry the IDs it had before, as `aliases=` in its marker or `aliases = [...]` in its front matter. A former ID still names the item, from this repository and from others, and stays taken: no other item may have it as its ID or as a former one.

## Items as files

%req[items.file]
In a source of item files, a Markdown file that starts with TOML front matter between `+++` lines shall be one item. The front matter gives the ID and, unless the source gives one, the item type. The rest of the file is the text of the item.

%req[items.file.keys]
The other keys of the front matter shall have the same meaning as in a marker: the status, the category, the verification method, links (a string or an array of strings, under a key that is a link type), or an attribute (a string, an integer, a boolean or a date).

%req[items.file.not-items]
In a source of item files, a Markdown file that does not start with front matter is not an item and shall be skipped. Front matter that is opened and not closed, or has no ID, is reported.

%req[items.sources]
The items of a project shall be read from every source, in the order of the sources, then of the files by path, then of the lines. Directories whose names start with a dot, and build outputs, are not read.

## References and citations

%req[items.reference]
In the text of an item, a marker without an item type, `%[id]` or `%[id words]`, shall be a reference to the item `id`. Skein records its line and column, and the words to show in place of the ID. Nothing inside a code span or a code block is a reference, and neither is a percent sign directly after a letter or a digit. Double brackets (`[[page]]`) have no meaning in Skein and are left to other tools.

%req[items.reference.narrative]
A reference in narrative text, which is the text of a document that does not belong to any item, shall be read too, with its file, line and column. It is checked by the same rules as a reference inside an item, and `skein trace` shows it with the item it names. It is not part of any fingerprint and does not make any link suspect.

%req[items.citation]
A citation set shall name a directory, the file name endings of the files to read, and a marker. In each such file, the IDs that follow the marker on a line are citations of those items by that set. The list of IDs ends at a full stop after an ID, or at a word that is not an ID.

%req[items.citation.directory]
A file named `.skein-cites` shall cite the IDs it lists on behalf of every file in its directory and below, for the citation sets that have files there.
