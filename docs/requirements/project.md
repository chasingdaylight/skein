# The project: configuration and schema

The files are described for their users in `docs/project-files.md`.

## Finding and reading the project

req[project.root]
A project is a directory with a `.skein/` directory in it. A command that works on a project shall find it from the directory it is run in, or the one `--root` names: the nearest directory, there or above, that is a project.

req[project.config]
`.skein/config.toml` shall give the project's name and its sources: for each, a directory, whether its Markdown files are documents or one item each, and for item files the item type of a file that names none.

req[project.paths]
A path in the configuration shall be written from the project's root with forward slashes, and shall not leave the project; one that does is reported.

req[project.files-by-name]
Each item type, link type and profile shall be declared by one TOML file, in `.skein/types/`, `.skein/links/` and `.skein/profiles/`, and its name is the file's name. A name is lowercase letters, digits, `-` and `_`, starting with a letter.

req[project.unknown-keys]
A key that skein does not know, in the configuration or in a file of the schema, shall be reported with the file and the key.

req[project.toml]
The files of `.skein/` and the front matter of items shall be TOML, read by skein's own reader: tables, arrays of tables, inline tables, strings of all four kinds, integers, floats, booleans, and dates and times.

req[project.toml.diagnostics]
TOML that cannot be read shall be reported with its file, line and column, and what is wrong there.

## The schema

req[schema.item-type]
An item type shall declare how its IDs are spelled: hierarchical (`lex.comment.line`), or numbered (`SRS-012`) with a prefix, a number of digits, a separator that may be empty, and whether a name may stand in the number's place.

req[schema.categories]
An item type may declare categories. An item of such a type has exactly one of them; an item of a type without categories has none.

req[schema.statuses]
An item type shall declare its statuses, or take the default ones (draft, approved, deprecated, removed). An item that names no status has the first.

req[schema.tombstone]
An item type may name one of its statuses as that of a removed item. A removed item keeps its ID taken.

req[schema.attributes]
An item type shall declare its attributes: for each, its kind (string, integer, boolean, date), the values it may take if it is a string with a fixed set, whether every item must have it, and whether it is part of what an item says.

req[schema.verification]
An item type may declare the verification methods an item of the type may name.

req[schema.link-type]
A link type shall declare which item types a link of it may start at and point to, whether every item it may start at must have one, whether every item it may point to should be pointed to by one, and whether its links are reviewed.

req[schema.profile]
A profile shall select items by any of: item types, categories, statuses, and attributes that must have one of the values given. An item is in the profile when it passes every condition given.

req[schema.reserved-names]
No attribute or link type shall have the name of a key skein reads itself (`id`, `type`, `status`, `category`, `verification`), and no attribute the name of a link type.

req[schema.cross-check]
What the parts of the schema say about each other shall be checked: a link type, a profile, a source or a citation set that names an item type the schema does not have is reported, and so is a profile that names a category, status or attribute that none of its item types has.
