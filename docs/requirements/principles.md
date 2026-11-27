# Principles

What holds for all of Skein. The reasons are in `docs/design.md`, section 2.

%req[principle.plain-text]
Everything Skein stores about a project shall be in plain text files in the repository of the project: the schema, the items, the review records and the approvals. Skein shall keep no database, and reading those files shall not depend on anything Skein derives from them.

%req[principle.git-only]
Every command that reads the current project shall work with nothing but the files. Skein shall need the `git` program only for what only git has or does: the name of the user; the content of the files at an earlier commit, their history and who last changed them; tags (`baseline.tag`); the other repositories it fetches (`network.fetched`); the commits, branches, worktrees, merges, pushes and pulls of `skein serve` and `approve --sign` (`serve.save`, `serve.team`); signatures (`approval.signed`); and the address of `origin` (`ci.engineering-docs`).

%req[principle.forge-neutral planned]
Skein shall reach a forge (GitHub, GitLab, Forgejo) only through an adapter, and no feature of Skein shall depend on something that one of the three lacks. Built: the adapters of all three (`forge.gitlab`, `forge.forgejo`). Still to do: publishing a mirror to Forgejo (`forge.publish`; issue #299). GitLab's requirements (`forge.gitlab-requirements`) and Jama Connect (`forge.jama`) are tools of their own that Skein keeps to the items, not features that need them.

%req[principle.schema-driven]
Skein shall have no built-in item type, link type, attribute, category or status. A project declares them, and Skein checks the items of the project against those declarations.

%req[principle.prose-friendly]
It shall be possible to write an item as a paragraph in a document that also contains text that is not an item, so that a specification reads as a document. It shall also be possible to write an item as a file of its own.

%req[principle.deterministic]
The same files shall give the same output, byte for byte. Problems, traces, coverage, exports and the record files Skein writes are in an order that does not depend on the machine, the file system or the run.

%req[principle.one-codebase]
Skein shall build from its own repository alone, into one program with no dependencies at run time. Nothing is fetched during the build, and Skein requires no other tool than `git`. It may use a tool the user has installed for what it does better, such as a forge's own program (`gh`, `glab`) for its sign-in, but does without it when it is not there (emanspeaks, 2026-11-22).

%req[principle.no-silent-mistakes]
Anything Skein cannot read as intended shall be reported, not ignored: an unknown key in a file of `.skein/`, an option that does not belong to a command, a reference to an item that does not exist.
