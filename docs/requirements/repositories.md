# Other repositories: links across them, and the state of the network

The user documentation is in `docs/repositories.md`.

A project's items can refer to the items of other repositories: a compiler's specification, cited by a website and an editor extension. Together they form a network of items. Its state is one commit of each repository, recorded by the project that declares them, and a check reads them at that state, so that it gives the same answer on every machine.

## Declaring them

%req[links.repositories]
Items, code and tests of another repository shall be citable by a qualified reference, checked against a recorded commit of that repository. (Design, section 10.5.)

%req[network.declared]
A project shall declare each other repository in `.skein/config.toml` under `[[repositories]]`, with the short name its targets use before the colon (`name:id`) and either the `path` of a checkout, from the project's root, or a `url` git can fetch from. A name given twice, a repository with both or neither, and a path that is absolute or has backslashes are reported. A project may give itself an `id` under `[project]`, which other projects know it by whatever short name they give it.

## The record

%req[network.record]
The recorded state shall be in `.skein/network.toml`, a file Skein writes and the project commits: for each repository, by its short name, the commit and the fingerprint of its items at that commit, which is a hash over the ID and fingerprint of each item, in order of ID. A record that Skein cannot read is reported, and a repository whose items at the recorded commit do not have the recorded fingerprint is reported as not what was pinned.

%req[pin.command]
`skein pin [NAME [REV]]` shall record the commit `REV` of the repository `NAME`, or the commit its checkout has checked out, or do so for each repository when no name is given, and write the record. For a repository pinned before at another commit, it says how many items were added, removed and changed between the two, and which of the removed and changed items the project's items link or refer to.

%req[pin.refusals]
`skein pin` shall refuse, and write nothing, when the project declares no repository or none of that name, when the project is not in a git repository, when a checkout is not there or has no such commit, and, when no commit is named, when the checkout has changes that are not committed: a state of the network is one of commits.

## Networks that nest

A repository can be the root of its own network and a member of others: a compiler's, a website's that includes the compiler, a workspace's that includes both. The project Skein is run for decides which commits are read.

%req[network.identity]
A repository shall be known by the `id` its own configuration declares, not by the short names others give it. Two declared repositories with the same identity, and a declared repository that is the project itself, are reported. When a member's own record has a repository at another commit than this network has it, that is a warning, and this network's commit is the one read.

%req[network.reached]
`skein pin` shall record, besides the declared repositories, each repository reached only through their records, by its identity, once, at the commit those records give, with the declared repositories it is reached through. When two of them record one at different commits, `pin` refuses and names them.

%req[network.submodules]
A declared repository whose path is a git submodule of the project shall be read, in the recorded state, at the commit git records for the submodule, and `skein pin` records nothing for it.

## Reviews, trace and rendering

%req[network.reviews]
A reviewed link to an item of another repository shall be held against that item's fingerprint in the state read, as a link within the repository is: never reviewed until `skein review` records it, and suspect when the item has changed since. In the recorded state, a change there makes the link suspect only once the commit that has it is pinned. `skein trace` shows such a target with its type, its repository, and the commit read, or why it could not be read.

%req[network.site]
A repository may give the address of its site, as `skein render --format html` writes it (`site`). A reference to one of its items is then rendered as a link to the item's page there, with the item's anchor when it is in a document; without a site, as its words.

## Repositories by URL

%req[network.fetched]
A repository declared by a `url` shall be fetched with git into a cache of its own, a bare repository under this repository's git directory that is never committed: the recorded commit, or, for `--current` and `--working`, the tip of its `ref` or of its default branch. A fetch that shows no progress for 30 seconds is stopped, and git is never let wait for a password typed at a terminal. `skein pin` fetches what it pins the same way: the commit named, a branch or tag named, or the tip.

%req[network.offline]
With `--offline`, nothing shall be fetched: a repository by url is read from what its cache holds. A repository whose commit is not in its cache, offline, or that could not be fetched, is not read, and the targets in it are not checked: a warning, as for a checkout that is not there.

## Reading the network

%req[network.states]
By default, every command that reads the other repositories shall read each at its recorded commit, from git, without changing its checkout. With `--current`, each is read at the commit its checkout has checked out; with `--working`, its files are read as they are on disk, committed or not. A repository not pinned yet, or whose checkout or commit is not there, is not read, and the targets in it are not checked.
