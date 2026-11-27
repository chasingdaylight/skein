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

Everything above works the same: `#97` is issue 97 of the project, a merge request's approvals are read for `skein approve --from-pull-request`, and the planning fields (assignees, milestone and its due date, closed) are read and written back by `skein apply`. Skein asks through `glab` when it is installed, so its sign-in is used; without it, it calls GitLab's API with the token in `GITLAB_TOKEN` when one is set (public projects need none).

### GitLab's requirements

GitLab Ultimate has requirements of its own, which a CI job can mark satisfied or failed. Skein keeps the items as the truth and gives GitLab a view of them, through the files GitLab reads and writes:

1. `skein export gitlab-requirements --profile NAME > requirements.csv` writes the items (removed ones left out) as the CSV GitLab's requirements import takes: the title is the item's ID, a colon and its first sentence (or its `title` attribute), the description its text. Import it in GitLab under Plan > Requirements.
2. Export the requirements from GitLab (it sends the CSV by email), then `skein import gitlab-requirements that-export.csv` records the requirement IID of each item in `.skein/gitlab-requirements.toml`, matched by the ID that starts the title; commit it. Archived requirements, and ones whose title names no item, are left out and listed.
3. In CI, `skein coverage --results junit.xml --gitlab-requirements requirements.json` also writes the requirements report: an item's requirement fails when a result of any implementation failed, passes when one passed and none failed, and is left out when untested. Upload it as the job's report:

```yaml
requirements:
  script:
    - skein coverage --results junit.xml --gitlab-requirements requirements.json
  artifacts:
    reports:
      requirements_v2: requirements.json  # requirements: on a project without work items
```

Run the first two steps again when items are added, or let the API do both: `skein gitlab-requirements [--profile NAME]` creates a requirement for each item that has none (recording it in the map), brings the title and description of the others back to their items, archives the requirements of removed items and reopens those of items that are back; `--dry-run` says what it would do. It works through `glab` when it is installed, else with the token in `GITLAB_TOKEN`, and needs work items with the Requirement type (Ultimate). Changes made in GitLab are undone by the next run: the items are the truth.

## Jama Connect

Jama Connect is not a forge, but a project whose truth is Skein can keep a Jama project to its items, for the people who read and review in Jama. `.skein/jama.toml`, written by hand, says where they go:

```toml
url = "https://example.jamacloud.com"
project = 42           # the Jama project's id
parent = 1201          # the folder or set new items go in; the project's root when left out

[types]                # the Jama item type (its id) of each item type that goes to Jama
requirement = 89

[links]                # the relationship type (its id) of each link type
derives = 4            # from the link's source to its target
verifies = { type = 5, reverse = true }   # from its target to its source, as "Verified By"
```

`skein jama [--profile NAME]` then brings Jama to the items. An item without a Jama item gets one, named by its ID and first sentence (as for GitLab) with its text as the description, and its id is recorded in `.skein/jama-map.toml`, which the project commits. An item whose Jama item says otherwise, compared as plain text since Jama rewrites the HTML it is given, has it brought back, and the run says so: someone changed it in Jama. A removed item's Jama item is reported and left, for its owners to delete. Each link of a type `[links]` names becomes a relationship between the two Jama items; a relationship of such a type between two mapped items that no link calls for is reported, to be linked in Skein or taken out of Jama. `--dry-run` asks Jama and changes nothing.

It signs in as `skein import jama` does, from `JAMA_CLIENT_ID` and `JAMA_CLIENT_SECRET`, else `JAMA_USERNAME` and `JAMA_PASSWORD`; in CI, from the job's secrets. The ids of item and relationship types are on Jama's admin pages, or in `GET /rest/v1/itemtypes` and `/relationshiptypes`. The requests follow Jama's REST reference (rest.jamasoftware.com) and Jama's Python client for the bodies it leaves out; they are tested against recorded answers, not a Jama instance, so try `--dry-run` first.

## Forgejo

```toml
[forge]
kind = "forgejo"
repository = "owner/repo"
# url = "https://git.example.com"   # for a server of one's own; codeberg.org otherwise
```

Everything of GitHub works the same here: `#97` is issue 97 of the repository, a pull request's approvals are read for `skein approve --from-pull-request` (a reviewer's last review that approved or asked for changes counts, and a dismissed one does not), and the planning fields are read and written back by `skein apply`. Forgejo has no program that holds a sign-in as `gh` and `glab` do, so Skein calls its API itself, with the token in `FORGEJO_TOKEN` (an access token with the issue scope): public repositories are read without one, and writing needs one. `skein publish --to forgejo:OWNER/REPO` re-creates a mirror there as on the others (`--url` for a server other than codeberg.org).

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
