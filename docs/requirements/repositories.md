# Other repositories: links across them, and the state of the network

The user documentation is in `docs/repositories.md`.

A project's items can refer to the items of other repositories: a compiler's specification, cited by a website and an editor extension. Together they form a network of items. Its state is one commit of each repository, recorded by the project that declares them, and a check reads them at that state, so that it gives the same answer on every machine.

## Declaring them

%req[network.declared]
A project shall declare each other repository in `.skein/config.toml` under `[[repositories]]`, with the short name its targets use before the colon (`name:id`) and either the `path` of a checkout, from the project's root, or a `url` git can fetch from. A name given twice, a repository with both or neither, and a path that is absolute or has backslashes are reported. A project may give itself an `id` under `[project]`, which other projects know it by whatever short name they give it.

## The record

%req[network.record]
The recorded state shall be in `.skein/network.toml`, a file skein writes and the project commits: for each repository, by its short name, the commit and the fingerprint of its items at that commit, which is a hash over the ID and fingerprint of each item, in order of ID. A record that skein cannot read is reported, and a repository whose items at the recorded commit do not have the recorded fingerprint is reported as not what was pinned.

%req[pin.command]
`skein pin [NAME [REV]]` shall record the commit `REV` of the repository `NAME`, or the commit its checkout has checked out, or do so for each repository when no name is given, and write the record. For a repository pinned before at another commit, it says how many items were added, removed and changed between the two, and which of the removed and changed items the project's items link or refer to.

%req[pin.refusals]
`skein pin` shall refuse, and write nothing, when the project declares no repository or none of that name, when the project is not in a git repository, when a checkout is not there or has no such commit, and, when no commit is named, when the checkout has changes that are not committed: a state of the network is one of commits.

## Reading the network

%req[network.states]
By default, every command that reads the other repositories shall read each at its recorded commit, from git, without changing its checkout. With `--current`, each is read at the commit its checkout has checked out; with `--working`, its files are read as they are on disk, committed or not. A repository not pinned yet, or whose checkout or commit is not there, is not read, and the targets in it are not checked.
