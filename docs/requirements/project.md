# The project: configuration and schema

The user documentation is in `docs/project-files.md`.

## Finding and reading the project

%req[project.root]
A project is a directory that contains a `.skein/` directory. A command that works on a project shall find it from the directory it is run in, or from the one `--root` names: the nearest directory, there or above, that is a project.

%req[project.config]
`.skein/config.toml` shall give the name of the project and its sources. Each source gives a directory, whether its Markdown files are documents or one item each, and, for item files, the item type to use when a file names none.

%req[project.paths]
A path in the configuration shall be relative to the project root, written with forward slashes, and shall not lead outside the project. A path that does is reported.

%req[project.files-by-name]
Each item type, link type and profile shall be declared by one TOML file, in `.skein/types/`, `.skein/links/` and `.skein/profiles/`, and takes its name from the file name. A name is lowercase letters, digits, `-` and `_`, starting with a letter.

%req[project.unknown-keys]
An unknown key, in the configuration or in a schema file, shall be reported with the file and the key.

%req[project.toml]
The files of `.skein/` and the front matter of items shall be TOML, read by the TOML reader that is part of skein: tables, arrays of tables, inline tables, strings of all four kinds, integers, floats, booleans, and dates and times.

%req[project.toml.diagnostics]
TOML that cannot be read shall be reported with its file, line and column, and a description of the error.

%req[project.toml.places]
A problem with a key or a value of a file of `.skein/` or of the front matter of an item file shall be reported at the line and column of the key in its file; a problem with a key that is missing, at the header of its table. Only what the whole file is missing is reported without a place.

## The schema

%req[schema.item-type]
An item type shall declare its ID scheme: hierarchical (`lex.comment.line`), or numbered (`SRS-012`) with a prefix, a number of digits, a separator that may be empty, and whether a name may be used in place of the number.

%req[schema.categories]
An item type may declare categories. An item of such a type has exactly one of them; an item of a type without categories has none.

%req[schema.statuses]
An item type shall declare its statuses, or take the default ones (draft, approved, deprecated, removed). An item that names no status has the first one.

%req[schema.tombstone]
An item type may name one of its statuses as the status of a removed item. The ID of a removed item stays reserved.

%req[schema.attributes]
An item type shall declare its attributes. Each attribute has a kind (string, integer, boolean, date), optionally a fixed set of allowed values if it is a string, whether every item must have it, and whether it is normative, that is, part of the content of an item.

%req[schema.verification]
An item type may declare the verification methods an item of the type may name.

%req[schema.link-type]
A link type shall declare which item types its links may start at and which they may point to, whether every item it may start at must have one, whether every item it may point to is expected to have one pointing to it, and whether its links are reviewed.

%req[schema.profile]
A profile shall select items by any of: item types, categories, statuses, and attributes that must have one of the given values. An item is in the profile when it meets every condition.

%req[schema.reserved-names]
No attribute or link type shall have the name of a key that skein itself reads (`id`, `type`, `status`, `category`, `verification`), and no attribute shall have the name of a link type.

%req[schema.cross-check]
References between parts of the schema shall be checked. A link type, a profile, a source or a citation set that names an item type the schema does not have is reported. So is a profile that names a category, status or attribute that none of its item types has.
