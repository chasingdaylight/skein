# Importing

The user documentation is in `docs/importing.md`.

%req[import.place]
An import shall work in the directory it is run in, or in the one `--root` names, and shall not look for a project above it. Its paths are relative to that directory. If there is no project there, the import creates one.

## From Doorstop

%req[import.doorstop.items]
`skein import doorstop` shall convert each item of a Doorstop document, stored as Markdown with YAML front matter or as YAML, into a Skein item file of the same name, in place. Files in the directory that are not items of the document are left unchanged.

%req[import.doorstop.type]
The settings of the document shall become an item type with numbered IDs (prefix, digits, separator, and names in place of numbers where the document uses them), with an attribute for each attribute its items use. The directory shall become a source of the project.

%req[import.doorstop.fields]
No data of an item shall be lost. Its links become `parent` links, an inactive item becomes a removed item, and every attribute becomes an attribute. An attribute keeps its name, unless Skein itself reads a key of that name, in which case it is named `doorstop-` followed by the name. The Doorstop category becomes the Skein category when every active item of the document has one.

%req[import.doorstop.reviews]
A link that Doorstop recorded as reviewed shall be recorded as reviewed, against the fingerprint its target has at the time of the import.

%req[import.doorstop.refusals]
A directory that is not a Doorstop document, a file that is not in the form Doorstop writes, and an item type that already exists shall each be refused, and nothing of that document shall be changed.

%req[import.doorstop.headings]
With `--headings-as-text`, an active item that Doorstop marks as not normative, and that no item of its document links to, shall be written as plain Markdown, its text alone, so that it is narrative and no item; whether the document's categories become Skein's is then decided by the items that remain.

%req[import.doorstop.statuses]
With `--status-from NAME`, the values of the attribute `NAME` shall be the items' statuses, in lowercase with other characters as `-`, and the item type's statuses those values in the order they come, with `removed` as the status of removed items. With `--verification-from NAME`, the same for the verification method and the type's methods. The attribute named is then not kept as an attribute.

## From CSV

%req[import.csv.rows]
`skein import csv` shall create an item file for each row of a CSV file whose first row names the columns. The ID and the text come from the columns named for them. The status, category and verification method come from columns with those names, links from columns named after link types, and attributes from the remaining columns. Empty cells are left out.

%req[import.csv.reader]
The file shall be read in the form spreadsheets write: a quoted field may contain the delimiter, doubled quotes and line endings. The delimiter is the semicolon when the first row has more semicolons than commas.

%req[import.csv.type]
When the project has no item type with the given name, one shall be created, with an attribute per attribute column and the ID scheme that the IDs follow. An existing item type is not changed. The directory becomes a source unless it already is one.

%req[import.csv.all-or-nothing]
Nothing shall be written unless every row can become an item and no existing item file would be overwritten. With `--replace`, existing files are overwritten.

## From ReqIF

%req[import.reqif]
`skein import reqif FILE --type TYPE --to DIR` shall make an item file of each spec object of a ReqIF 1.2 file, as `import csv` does of each row (with its item type, sources, refusals and `--replace`), in the order of the file's specifications: the ID from the attribute `id` (as `skein export reqif` writes it), else `ReqIF.ForeignID`, else the object's identifier; the text from the XHTML attribute `text` or `ReqIF.Text`, else the first XHTML one, as Markdown; the identifier as the attribute `reqif`; `ReqIF.Name` as the attribute `title`; the other attributes by their long names, an enumeration as the names of its values; and each spec relation as a link of the type named as the relation type, to the item its target became. What `skein export reqif` writes comes back as the same items. (Issue #241.)

%req[import.jama]
`skein import jama PROJECT --jama-type KEY --type TYPE --to DIR` shall make an item file of each item of the Jama item type KEY of the Jama Connect project PROJECT (its id), read through Jama's REST API page by page, as `import reqif` does of each spec object: the ID from the item's document key; its description (HTML) as Markdown; its name as the attribute `title`, its id as `jama` and its item type as `jama-type`; and each relationship from it as a link of the type named as the relationship type, to the item of any type the relationship goes to. A Jama item type is taken a time, as a Skein type has one scheme of IDs. The instance is `url` in `.skein/jama.toml`, else `JAMA_URL`, and the sign-in is as `skein jama`'s. (Issue #251.)
