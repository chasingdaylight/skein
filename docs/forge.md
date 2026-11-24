# The forge: issues and pull requests

Items can name issues and pull requests: the pull request that introduced a rule, the issue that tracks one that is not done. Name the forge once:

```toml
# .skein/config.toml
[forge]
kind = "github"
repository = "example/spec"
# url = "https://github.example.com"   # for GitHub Enterprise
```

Then `#97` is issue or pull request 97 of `example/spec`, and `other/repo#12` one of another repository, in links and references alike:

```markdown
%rule[lex.comment introduced-by=#97 tracked-by=#103] A comment runs to the end of the line; see %[other/repo#12].
```

## What `check` says of them

`skein check` asks the forge about each one, once per run:

- one that does not exist is a problem;
- one that a link of a type with `open = true` points to, while it is closed, is a problem: a `tracked-by` link to an issue that was closed without the item changing, say.

```toml
# .skein/links/tracked-by.toml
open = true
```

Skein asks through `gh` when it is installed, so its sign-in is used, GitHub Enterprise included. Without `gh`, it calls GitHub's API itself, with the token in `GH_TOKEN` or `GITHUB_TOKEN` when one is set; public repositories need none. Nothing has to be installed for it.

## GitLab

```toml
[forge]
kind = "gitlab"
repository = "group/sub/project"
# url = "https://gitlab.example.com"   # for a self-managed server
```

Everything above works the same: `#97` is issue 97 of the project, a merge request's approvals are read for `skein approve --from-pull-request`, and the planning fields (assignees, milestone and its due date, closed) are read and written back by `skein apply`. Skein asks through `glab` when it is installed, so its sign-in is used; without it, it calls GitLab's API with the token in `GITLAB_TOKEN` when one is set (public projects need none). Forgejo's adapter is still to come.

## Rendered

`skein render` makes each reference a link to the issue or pull request on the forge. A reference that gives no words of its own is followed by its title and state, as the forge or the cache has them: `#97 (Proposal 0000, closed)`. One the forge says does not exist is marked unresolved, as a missing item is.

## Approvals from a merged pull request

A review that approved a pull request is an approval of what it changed. After the merge, `skein approve --from-pull-request 97` records it: every item the pull request added or changed in content is approved, as it was at the merge, by each reviewer whose last review approved, on the day of the merge. An approval given after the merge counts as well: a retroactive approval is still an approval. A workflow can run it when a pull request is merged; `check` never does.

```text
$ skein approve --from-pull-request 97
skein: pull request 97, merged 2026-11-21: 3 items approved by ann, carol
```

## Offline

What the forge said is kept in a cache under `.git/skein/forge/`, never committed. With `--offline`, Skein asks nothing and uses the cache; when the forge cannot be reached, it uses the cache too. What neither knows is not checked, and `check` says so with a warning:

```text
.skein/config.toml: warning: forge: 6 references to issues and pull requests are not checked: no network
```

Without `[forge]`, references to issues and pull requests are accepted without being checked.

## A full mirror: working offline for long, and moving between forges

For longer than the cache serves, `skein mirror` copies everything the forge holds of the project's repository (every issue and pull or merge request with its comments, every milestone and the labels) into `.skein/mirror/`, in plain text, one file each: `issues/12.toml`, `pulls/7.toml`, `milestones/4.toml`, `labels.toml`. The mirror is per checkout: git ignores it, and `skein mirror` rebuilds it. To commit it instead, for a team that works offline together or to keep an archive that outlives the forge:

```toml
[forge]
repository = "example/spec"
mirror = "committed"
```

Offline, `check` and the views take what the mirror says of an issue when neither the forge nor the cache can answer. Changes to what the forge holds are made as an overlay (`skein overlay`), each with the value it was based on. Back online, `skein sync` writes the overlay to the forge, as `skein apply` does (a field changed on both sides is reported and left), and refreshes the mirror.

To move the project to another forge, mirror the old one, then create its issues on the new:

```text
skein mirror
skein publish --to gitlab:group/project --dry-run
skein publish --to gitlab:group/project
```

`skein publish` creates the labels, milestones and issues with their comments, and closes the ones that were closed. Each issue says where it came from and who opened it. Pull and merge requests are not re-created, since a forge cannot make one without its branches, and nobody is assigned, as the new forge may not know the people. `.skein/forge-map.toml`, which the project commits, records where each issue went (`"github:example/spec#24" = "gitlab:group/project#7"`). ### References after a move

Older items and commits say `#24`, which is now the new forge's issue 24, or, written for the old forge, what became issue 7 there. Name the old forge once, and Skein reads the map:

```toml
[forge]
kind = "gitlab"
repository = "group/project"
formerly = ["github:example/spec"]
```

A bare `#24` is looked up in `.skein/forge-map.toml` first; when the map has it, the reference is the new issue 7, and `skein check` warns that it is the old number, so the pages and checks are right at once. A number the map does not have is the new forge's own. `github:example/spec#24` always names the issue of the old forge, resolved the same way; one the map does not have is reported as not found.

`skein rewrite-refs` ends the transition: it writes the new number into those references (`%[#24]`, `tracked-by=#24` in a marker, `"#24"` in front matter) and nowhere else, never in prose, a code block or a color, and never in a read-only source. `--dry-run` says what it would write. An issue that kept its number (`#57` to `#57`) needs nothing and is not warned of. Once the references are rewritten, remove `formerly`: while it stays, a new number that is also an old one in the map is read as the old one.
