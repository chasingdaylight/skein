# Importing

The user documentation is in `docs/importing.md`.

%req[import.place]
An import shall work in the directory it is run in, or in the one `--root` names, and shall not look for a project above it. Its paths are relative to that directory. If there is no project there, the import creates one.

## From Doorstop

%req[import.doorstop.items]
`skein import doorstop` shall convert each item of a Doorstop document, stored as Markdown with YAML front matter or as YAML, into a skein item file of the same name, in place. Files in the directory that are not items of the document are left unchanged.

%req[import.doorstop.type]
The settings of the document shall become an item type with numbered IDs (prefix, digits, separator, and names in place of numbers where the document uses them), with an attribute for each attribute its items use. The directory shall become a source of the project.

%req[import.doorstop.fields]
No data of an item shall be lost. Its links become `parent` links, an inactive item becomes a removed item, and every attribute becomes an attribute. An attribute keeps its name, unless skein itself reads a key of that name, in which case it is named `doorstop-` followed by the name. The Doorstop category becomes the skein category when every active item of the document has one.

%req[import.doorstop.reviews]
A link that Doorstop recorded as reviewed shall be recorded as reviewed, against the fingerprint its target has at the time of the import.

%req[import.doorstop.refusals]
A directory that is not a Doorstop document, a file that is not in the form Doorstop writes, and an item type that already exists shall each be refused, and nothing of that document shall be changed.

## From CSV

%req[import.csv.rows]
`skein import csv` shall create an item file for each row of a CSV file whose first row names the columns. The ID and the text come from the columns named for them. The status, category and verification method come from columns with those names, links from columns named after link types, and attributes from the remaining columns. Empty cells are left out.

%req[import.csv.reader]
The file shall be read in the form spreadsheets write: a quoted field may contain the delimiter, doubled quotes and line endings. The delimiter is the semicolon when the first row has more semicolons than commas.

%req[import.csv.type]
When the project has no item type with the given name, one shall be created, with an attribute per attribute column and the ID scheme that the IDs follow. An existing item type is not changed. The directory becomes a source unless it already is one.

%req[import.csv.all-or-nothing]
Nothing shall be written unless every row can become an item and no existing item file would be overwritten. With `--replace`, existing files are overwritten.
