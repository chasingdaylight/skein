# Principles

What holds for all of skein. The reasons are in `docs/design.md`, section 2.

%req[principle.plain-text]
Everything skein stores about a project shall be in plain text files in the repository of the project: the schema, the items, the review records and the approvals. skein shall keep no database, and reading those files shall not depend on anything skein derives from them.

%req[principle.git-only]
Every command that reads the current project shall work with nothing but the files. skein shall need the `git` program only for information that only git has: the name of the user, and the content of the files at an earlier commit.

%req[principle.forge-neutral planned]
skein shall reach a forge (GitHub, GitLab, Forgejo) only through an adapter, and no feature of skein shall depend on something that one of the three lacks.

%req[principle.schema-driven]
skein shall have no built-in item type, link type, attribute, category or status. A project declares them, and skein checks the items of the project against those declarations.

%req[principle.prose-friendly]
It shall be possible to write an item as a paragraph in a document that also contains text that is not an item, so that a specification reads as a document. It shall also be possible to write an item as a file of its own.

%req[principle.deterministic]
The same files shall give the same output, byte for byte. Problems, traces, coverage, exports and the record files skein writes are in an order that does not depend on the machine, the file system or the run.

%req[principle.one-codebase]
skein shall build from its own repository alone, into one program with no dependencies at run time. Nothing is fetched during the build, and skein requires no other tool than `git`. It may use a tool the user has installed for what it does better, such as a forge's own program (`gh`, `glab`) for its sign-in, but does without it when it is not there (emanspeaks, 2026-11-22).

%req[principle.no-silent-mistakes]
Anything skein cannot read as intended shall be reported, not ignored: an unknown key in a file of `.skein/`, an option that does not belong to a command, a reference to an item that does not exist.
