# The project: configuration and schema

The user documentation is in `docs/project-files.md`.

## Finding and reading the project

%req[project.root]
A project is a directory that contains a `.skein/` directory. A command that works on a project shall find it from the directory it is run in, or from the one `--root` names: the nearest directory, there or above, that is a project.

%req[project.config]
`.skein/config.toml` shall give the name of the project and its sources. Each source gives a directory, whether its Markdown files are documents or one item each, and, for item files, the item type to use when a file names none.

%req[project.paths]
A path in the configuration shall be relative to the project root, written with forward slashes, and shall not lead outside the project. A path that does is reported.

%req[standards.read-only]
A source with `read_only = true` shall be read and checked as any other, and `skein move`, `skein link` and `skein new` shall refuse, changing nothing, to write to a file of it; a rename that would change such a file is refused whole. This is for an external standard, which is imported again, not edited.

%req[standards.waivers]
A link type may count as another (`counts_as`) or excuse from it (`excuses`), not both. For the coverage of the other link type, an item with a link of the first kind is covered (`counts_as`), or is waived (`excuses`): listed as waived and counted neither as covered nor as not, so that an item whose every requirement is met or waived is at 100%. Such a link counts only while the item it comes from is in force: not removed, and, when its type asks for approval, in one of the statuses that need it. A generated matrix of the other link type names the link (`tailors by ...`) or the waiver (`waived by ...`), and counts the waived apart.

%req[standards.external]
A standard the project must comply with shall be an item set of its own, read-only, which the project's items link to, with applicability by profile and with waivers and deviations as item types. (Design, section 4.7.) Built: `standards.read-only`, `standards.waivers`, profiles, and generated matrices.

%req[project.files-by-name]
Each item type, link type and profile shall be declared by one TOML file, in `.skein/types/`, `.skein/links/` and `.skein/profiles/`, and takes its name from the file name. A name is lowercase letters, digits, `-` and `_`, starting with a letter.

%req[project.unknown-keys]
An unknown key, in the configuration or in a schema file, shall be reported with the file and the key.

%req[project.toml]
The files of `.skein/` and the front matter of items shall be TOML, read by the TOML reader that is part of Skein: tables, arrays of tables, inline tables, strings of all four kinds, integers, floats, booleans, and dates and times.

%req[project.toml.diagnostics]
TOML that cannot be read shall be reported with its file, line and column, and a description of the error.

%req[project.toml.places]
A problem with a key or a value of a file of `.skein/` or of the front matter of an item file shall be reported at the line and column of the key in its file; a problem with a key that is missing, at the header of its table. Only what the whole file is missing is reported without a place.

## The schema

%req[schema.item-type]
An item type shall declare its ID scheme: hierarchical (`lex.comment.line`), or numbered (`SRS-012`) with a prefix, a number of digits, a separator that may be empty, and whether a name may be used in place of the number. A numbered ID may go on with a part's name after a dot (`SRS-012.a`), in lowercase words as hierarchical IDs have. Every key of an item type's file has a default, so an empty file is a type; item types, link types and profiles may each say what they are for (`description`).

%req[schema.categories]
An item type may declare categories. An item of such a type has exactly one of them; an item of a type without categories has none.

%req[schema.statuses]
An item type shall declare its statuses, or take the default ones (draft, approved, deprecated, removed). An item that names no status has the first one.

%req[schema.tombstone]
An item type may name one of its statuses as the status of a removed item. The ID of a removed item stays reserved.

%req[schema.attributes]
An item type shall declare its attributes. Each attribute has a kind (string, integer, boolean, date), optionally a fixed set of allowed values if it is a string, whether every item must have it, and whether it is normative, that is, part of the content of an item.

%req[schema.attribute-lists]
An attribute declared with `list = true` shall hold several values: given as `classes=A,B,C`, key by key (`classes=A classes=B`), or as a TOML array in front matter. Each value is held to what the attribute allows; a profile's or a generated list's condition on it is met when one of the values matches; `trace` shows the values joined by commas, and its JSON an array. An attribute without `list` takes one value, as before.

%req[schema.verification]
An item type may declare the verification methods an item of the type may name.

%req[schema.link-type]
A link type shall declare which item types its links may start at and which they may point to, whether every item it may start at must have one, whether every item it may point to is expected to have one pointing to it, and whether its links are reviewed.

%req[schema.profile]
A profile shall select items by any of: item types, categories, statuses, and attributes that must have one of the given values. An item is in the profile when it meets every condition.

%req[schema.reserved-names]
No attribute or link type shall have the name of a key that Skein itself reads (`id`, `type`, `status`, `category`, `verification`), and no attribute shall have the name of a link type.

%req[schema.cross-check]
References between parts of the schema shall be checked. A link type, a profile, a source or a citation set that names an item type the schema does not have is reported. So is a profile that names a category, status or attribute that none of its item types has.
