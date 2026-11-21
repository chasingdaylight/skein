# Items, references and citations

Described for their users in `docs/writing-items.md`.

## Reading Markdown

%req[markdown.blocks]
skein shall read the block structure of a Markdown file: headings, paragraphs, lists (also over blank lines), fenced and indented code, block quotes, tables, HTML blocks and thematic breaks, each with its first and last line. What is inside a code block is never anything else.

%req[markdown.line-ends]
A file with CRLF line ends shall give the same blocks, the same items and the same fingerprints as the same file with LF line ends.

%req[markdown.yaml-front-matter]
YAML between `---` lines at the top of a file, as site generators and other tools write it, shall be passed over: it is no item and holds none.

## Items in documents

%req[items.marker]
In a document, a marker at the start of a paragraph or of a list entry shall make it an item: a percent sign, an item type, and in brackets the ID and optionally more words, as in `%rule[lex.comment syntax]`.

%req[items.marker.inline]
The item's text shall follow its marker on the same line, or start on the next line.

%req[items.list-entries]
An entry of a list, at any depth, shall be an item when it starts with a marker.

%req[items.marker.types-only]
Only a percent sign, a lowercase name and an opening bracket at the start of a paragraph or of a list entry shall be a marker; the same elsewhere in a line, and anything in a code block, is text. A marker that names no item type of the project is reported.

%req[items.marker.words]
After the ID, a bare word is the category or the status, whichever of the type's it is, at most one of each; `key=value` gives the status, the verification method, links (when the key is a link type) or an attribute. Several values are separated by commas; a value in double quotes may hold spaces, and a closing bracket.

%req[items.marker.mistakes]
A marker that is not closed, has no ID, or has words that cannot be read so shall be reported, with its place, and make no item.

%req[items.text-extent]
An item's text shall be the rest of its marker's block, or the block after a marker that stands alone, and the lists, code blocks, tables and quotes that follow that block directly. A paragraph after it is no part of it. A marker with no text is reported.

%req[items.parts]
An entry with a marker, in a list that is in an item's text, shall be a part of that item: an item of its own, which records its whole, as the whole records its parts in their order. Parts may have parts. An item stands before its parts in the order of items.

%req[items.parts.names]
A part's ID that starts with a dot shall be its whole's ID followed by it; an ID without the dot is as written. A leading dot on an item that is part of none, or where the IDs of the part's type or of the whole's are not joined by dots, is reported.

%req[items.parts.text]
A part's text shall be its own, and no part of its whole's text. The whole's own text is its text without its parts: of a list with parts, the entries that do not start with a marker.

%req[items.removed]
A marker with its type's status for removed items shall be an item without text: the marker alone.

## Items as files

%req[items.file]
A Markdown file that starts with TOML front matter between `+++` lines, in a source of item files, shall be one item: the front matter gives its ID and, unless the source gives one, its type; the rest of the file is its text.

%req[items.file.keys]
The other keys of the front matter shall mean what they mean in a marker: the status, the category, the verification method, links (a string or an array of strings, under a key that is a link type), or an attribute (a string, an integer, a boolean or a date).

%req[items.file.not-items]
In a source of item files, a Markdown file that does not start with front matter is no item and shall be passed over. Front matter that is opened and not closed, or has no ID, is reported.

%req[items.sources]
The items of a project shall be read from every source, in the order of the sources, the files by path, and the lines; directories whose names start with a dot, and build outputs, are not read.

## References and citations

%req[items.reference]
In an item's text, a marker without an item type, `%[id]` or `%[id words]`, shall be a reference to the item `id`, with its line and column and the words to show in place of the ID. Nothing inside a code span or a code block is a reference, nor is a percent sign after a letter or a digit. Double brackets (`[[page]]`) are not skein's and are left to other tools.

%req[items.citation]
A citation set shall name a directory, the ends of the names of the files to read, and a marker; in each such file, the IDs after the marker on a line are citations of those items by that set. A full stop after an ID, or a word that is no ID, ends them.

%req[items.citation.directory]
A file named `.skein-cites` shall cite the IDs it lists for the files of its directory and below, for the citation sets that have files there.
