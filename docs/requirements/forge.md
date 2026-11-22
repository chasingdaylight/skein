# The forge: issues and pull requests

The user documentation is in `docs/forge.md`.

Items can name the issues and pull requests that introduced them, track them, or are tracked by them. Those are the forge's, so skein asks the forge about them; it keeps none of them itself.

%req[forge.refs]
`.skein/config.toml` shall name the project's forge under `[forge]`: its `kind` (`github` or `gitlab`; `forgejo` later), its `repository` (`owner/repo`), and the `url` of a server other than the public one. A link, reference or citation whose target is `#N` names issue or pull request N of that repository, and `owner/repo#N` one of another. Without `[forge]`, such targets are accepted unchecked.

%req[forge.check]
`skein check` shall report a target that the forge says does not exist, and one that a link of a type with `open = true` points to while it is closed. It asks the forge through the `gh` program when it is installed, so that its sign-in is used, and otherwise through the forge's HTTPS API with a token from `GH_TOKEN` or `GITHUB_TOKEN` when one is set; each issue or pull request is asked about once per run.

%req[forge.render]
`skein render` shall render a reference to an issue or pull request as a link to its page on the forge, followed, when the reference gives no words of its own, by its title and whether it is open or closed, as the forge or the cache gives them. One the forge says does not exist is marked unresolved; without `[forge]`, it is its words.

%req[forge.approvals]
`skein approve --from-pull-request N` shall record the approvals that merged pull request N had in review: each item it added or changed in content, between its base and its merge commit, approved as it was at the merge by each reviewer whose last review approved it (comments count for neither), on the day of the merge. It refuses a pull request that does not exist or is not merged, and a project that names no forge. It is run by hand or by a workflow after a merge, never by `check`.

%req[forge.gitlab]
With `kind = "gitlab"`, skein shall give the same answers from GitLab (gitlab.com, or the `url` of a self-managed server) as from GitHub: an issue's title, whether it is open, its assignees, its milestone and when it is due, writing them back for `skein apply`, and the merge request and its approvals for `skein approve --from-pull-request`. It asks through the `glab` program when it is installed, so that its sign-in is used, and otherwise through GitLab's HTTPS API with a token from `GITLAB_TOKEN` when one is set. A reference `#N` is an issue; its page is `/-/issues/N`; a repository may be a nested group, `group/sub/project`. (Issue #99; `principle.forge-neutral`.)

%req[forge.offline]
What the forge said of each issue and pull request shall be kept in a cache under this repository's git directory, never committed. With `--offline` nothing is asked and the cache is used; when the forge cannot be asked or does not answer, the cache is used too. What neither knows is not checked, and that is a warning.
