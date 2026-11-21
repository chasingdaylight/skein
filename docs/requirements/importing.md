# Importing

For their users: `docs/importing.md`.

req[import.place]
An import shall work in the directory it is run in, or the one `--root` names, and shall not look for a project above it: its paths are from that directory. Where there is no project, it makes one.

## From Doorstop

req[import.doorstop.items]
`skein import doorstop` shall turn each item of a Doorstop document, kept as Markdown with YAML front matter or as YAML, into a skein item file of the same name, in place. Files of the directory that are not the document's items are left as they are.

req[import.doorstop.type]
The document's settings shall become an item type with numbered IDs (prefix, digits, separator, and names in the number's place where the document has them), with an attribute for each one its items use; and the directory a source of the project.

req[import.doorstop.fields]
Nothing an item holds shall be lost: its links become `parent` links, an inactive item a removed one, and every attribute an attribute, under its own name or, where skein reads a key of that name itself, under `doorstop-` and its name. Its category is skein's when every active item of the document has one.

req[import.doorstop.reviews]
A link that Doorstop had a review of shall be recorded as reviewed, as its target is at the import.

req[import.doorstop.refusals]
A directory that is no Doorstop document, a file that is not what Doorstop writes, and an item type that exists already shall be refused, with nothing of that document changed.

## From CSV

req[import.csv.rows]
`skein import csv` shall make an item file of each row of a CSV file whose first row names the columns: the ID and the text from the columns named for them, the status, category and verification method from columns of those names, links from columns named after link types, and attributes from the others. Empty cells are left out.

req[import.csv.reader]
The file shall be read as spreadsheets write CSV: fields in quotes may hold the delimiter, doubled quotes and line ends; semicolons are the delimiter when the first row has more of them than commas.

req[import.csv.type]
When the project has no item type of the name given, one shall be made, with an attribute per such column and the ID scheme the IDs show. An item type that exists is not changed. The directory becomes a source unless it is one.

req[import.csv.all-or-nothing]
Nothing shall be written unless every row can be an item and no item file would be written over; with `--replace`, files that are there are written over.
