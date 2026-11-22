# Other repositories

A project's items can refer to the items of other repositories. A language's specification lives with its compiler; its website and its editor extension cite the rules they follow. Each such repository is declared once, and its items are then named as `name:id`.

## Declaring them

```toml
# .skein/config.toml
[project]
name = "website"
id = "example/website"

[[repositories]]
name = "compiler"
path = "../compiler"
```

`name` is the short name the targets use before the colon. `path` is a checkout on disk, from the project's root: a sibling checkout, or a submodule. A repository can give itself an `id`, which other projects know it by whatever short name they use.

Then links, references and citations can point into it:

```markdown
\%page[syntax explains=compiler:lex.comment] A comment is %[compiler:lex.comment.line text from // to the end of the line].
```

A repository that is not checked out beside this one can be given by its address instead, which git fetches:

```toml
[[repositories]]
name = "compiler"
url = "https://github.com/example/compiler.git"
ref = "main"
```

skein fetches it with git, so any address and sign-in git has works, SSH included, into a cache under `.git/skein/repositories/` that is never committed. `ref` is the branch or tag that `--current` follows; without it, the default branch. With `--offline`, skein fetches nothing and reads what the cache holds.

## Pinning: the state of the network

The items of the repositories together are a network, and a state of it is one commit of each repository. The project records the state it was last checked against in `.skein/network.toml`, which `skein pin` writes and the project commits:

```text
$ skein pin
compiler: pinned at 1a2b3c4d5e6f (412 items)
skein: wrote .skein/network.toml
```

From then on, `skein check` reads the compiler's items at that commit, from git, whatever its checkout has checked out, so the check gives the same answer on every machine and in CI. It reports a target that is not declared, an item the other repository does not have at that commit, and an item that is removed there.

When the compiler moves on, pinning again says what changed there and which of the changed items this project refers to:

```text
$ skein pin compiler
compiler: 1a2b3c4d5e6f to 9f8e7d6c5b4a: 3 added, 0 removed, 2 changed
  compiler:lex.comment is changed; referred to by syntax
skein: wrote .skein/network.toml
```

Someone looks at those, and the record is committed with whatever the change needs here. `skein pin compiler v1.2` pins a named commit or tag instead. A checkout with changes that are not committed is refused: a state of the network is one of commits.

## Other states

The states between recorded ones can still be looked at, where links may be broken:

| Option | Reads each other repository |
| --- | --- |
| (none) | At the commit `.skein/network.toml` records. |
| `--current` | At the commit its checkout has checked out, so switching a branch there and running again shows the other branch. |
| `--working` | As its files are on disk, committed or not, to try a change across repositories before committing it. |

`check`, `trace`, `coverage`, `export` and `render` take them, and `--offline` too. A repository by url has no working tree, so `--working` reads it as `--current` does.

## Reviews, trace and rendering

A link type with `review = true` is reviewed across repositories as within one: `skein review` records the target's fingerprint, and `check` reports the link as suspect once the target has changed. Since the other repository is read at its recorded commit, a change there makes the link suspect when that change is pinned, which is when someone looks.

`skein trace` shows a target in another repository with its type, the repository and the commit read.

`skein render` links a reference into another repository to the item on that repository's site, when the repository gives one:

```toml
[[repositories]]
name = "compiler"
path = "../compiler"
site = "https://example.org/compiler"
```

Without a site, the reference is its words. A reference that cannot be resolved, here or there, is rendered as its words marked as unresolved, which the site shows in red, so that a document can still be built, and read, while a link is broken.

## When a repository is not at hand

A repository that is not pinned yet, whose checkout is not there, whose checkout does not have the recorded commit, or that could not be fetched (offline, or no answer for 30 seconds), is not read. Its targets are then not checked, and `check` says so with a warning rather than a problem:

```text
.skein/config.toml: warning: repositories: compiler: there is no checkout at '../compiler', so 14 references to it are not checked
```

So a repository can be checked alone, and checked fully where its network is checked out.
