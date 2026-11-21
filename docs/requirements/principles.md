# Principles

What holds for all of skein. The reasons are in `docs/design.md`, section 2.

%req[principle.plain-text]
Everything skein holds about a project shall be in plain text files in the project's repository: the schema, the items, the review records and the approvals. skein shall keep no database, and nothing it derives from the files shall be needed to read them.

%req[principle.git-only]
Every command that reads the project as it is shall work with nothing but the files. skein shall need the `git` program only for what git alone knows: the user's name, and what the files said at an earlier commit.

%req[principle.forge-neutral planned]
skein shall reach a forge (GitHub, GitLab, Forgejo) only through an adapter, and no feature of skein shall depend on something one of the three lacks.

%req[principle.schema-driven]
skein shall have no item type, link type, attribute, category or status of its own: a project declares them, and skein holds the project's items to what it declares.

%req[principle.prose-friendly]
An item shall be writable as a paragraph in a document that also holds text that is no item, so that a specification reads as a document; and as a file of its own.

%req[principle.deterministic]
The same files shall give the same output, byte for byte: problems, traces, coverage, exports and the record files skein writes are in an order that does not depend on the machine, the file system or the run.

%req[principle.one-codebase]
skein shall build from its own repository alone, into one program without dependencies at run time: nothing is fetched when it is built, and no other tool is run but `git`.

%req[principle.no-silent-mistakes]
What skein cannot read as the project meant it shall be reported, not ignored: a key it does not know in a file of `.skein/`, an option that does not go with a command, a reference to nothing.
