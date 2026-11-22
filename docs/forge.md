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

skein asks through `gh` when it is installed, so its sign-in is used, GitHub Enterprise included. Without `gh`, it calls GitHub's API itself, with the token in `GH_TOKEN` or `GITHUB_TOKEN` when one is set; public repositories need none. Nothing has to be installed for it.

## Offline

What the forge said is kept in a cache under `.git/skein/forge/`, never committed. With `--offline`, skein asks nothing and uses the cache; when the forge cannot be reached, it uses the cache too. What neither knows is not checked, and `check` says so with a warning:

```text
.skein/config.toml: warning: forge: 6 references to issues and pull requests are not checked: no network
```

Without `[forge]`, references to issues and pull requests are accepted without being checked.
