# The web interface

`skein serve` shows the project's site in a browser and edits its files from there, for anyone who does not work in an editor: a reviewer, a manager, an author away from VS Code. The files stay the truth; what the pages change is written into them as an editor would write it.

```text
$ skein serve
skein: serving calc at http://127.0.0.1:8080/ until stopped (Ctrl+C)
```

## Reading

The site is the one `skein render --format html` writes, rendered from the files as they are, committed or not. When a file of the project changes (in an editor, by `git pull`, from a page), the site is rendered again and every open page loads itself again. A configuration or schema with problems is a page that says them, until they are fixed.

## Editing a file

**Edit this file**, at the bottom of a page of a document or item file, opens its Markdown beside the page. As you type, the problems `skein check` would find with the file as it is in the box are listed under it, with their lines, and how many the other files have. **Save** writes the file.

## Editing an item

Each item on a page has an **edit** button by its ID. Its form has the fields its type declares: category, status, verification method, each attribute (a list to pick from where the type gives the values), and each link type it may have, with the IDs of the items it may point to offered as you type. The problems `check` finds with the values as they are in the form are listed under it. **Save** writes them into the item's marker or front matter, as the language server's forms do; the item's text is changed with **Edit this file**.

**New item** opens the same form for a new item: its type, its ID (empty for the next number of a numbered type), the document it goes at the end of when its type is written in documents, and its text. Saving starts it as `skein new` does.

## How a save reaches git

The project chooses, in `.skein/config.toml`:

```toml
[serve]
save = "branch"     # or "pull-request", or "commit"
branch = "dev"      # where changes go; by default the branch checked out when skein serve started
editors = ["A. Person"]   # with "commit": who commits
```

| `save` | A save | Reviewed | Default |
| --- | --- | --- | --- |
| `pull-request` | goes into a change, a branch `edit/NAME`, committed there. **Propose** pushes it and opens a pull request into `branch` on the forge. | On the forge, before it is merged; `skein approve --from-pull-request` records the approvals. | With a `[forge]`. |
| `branch` | goes into a change, committed there. **Merge into** the branch merges it, with a merge commit, and deletes the branch. | In the interface, before it is merged. | Without a `[forge]`. |
| `commit` | is a commit on `branch`. | After: a changed item loses its approval, and its approvers approve it again ([reviewing](reviewing.md#approvals)). | Never. |

Each change is worked on in a git worktree of its own, under the repository's git directory (`.git/skein/changes/NAME`), so the checkout that serves stays on `branch`, and several changes are edited at once. While a change is open, the pages show it: its files, rendered as they are in the change. The bar at the bottom of each page says which change is open, and offers to merge, propose, leave or abandon it. With none open, it lists the changes there are, and **Start a change** names a new one, in lowercase letters, digits and dashes (`fix-lexing`); a save when no change is open asks for its name. Each commit is by the person signed in or, on this computer alone, by git's user (`git config user.name`). When `branch` has an upstream, it is pulled before a change starts from it and pushed after a merge, or after each commit with `commit`. Without git, a save is written and not committed.

### What `check` warns of

A checkout cannot stop anyone from committing as they like, so Skein says when the chosen way was not followed, and refuses nothing (emanspeaks, 2026-11-27). From the commit that set `save` on, `skein check` warns of:

- with `commit` and `editors`: commits to the sources by anyone not listed;
- with `branch` or `pull-request`: commits straight on `branch` that were not merged from a change. A squashed pull request, whose subject ends in `(#12)`, counts as merged.

## When the file changed meanwhile

A page remembers the file as it read it. If the file changed since (someone saved it in an editor, or a pull brought a change), **Save** writes nothing and says so: copy your change, close the box, and the page loads the file as it is now. While a box is open, the page does not load itself again, so nothing you typed is lost.

## Approving an item

An item whose type asks for approvals (`approval = [...]`, see [reviewing](reviewing.md#approvals)) has **Approve** in its form, with the roles to approve in where the type names them. It records an approval of the item as it is, as `skein approve` does, by the person signed in (on this computer alone, by git's user), and is saved as any edit is: in the open change, or as a commit. With people signed in, the record keeps how the approver was signed in: the electronic signature that an approval which must be signed counts by. With `[serve] approve_sign_in = "again"`, such an approval first sends the person to sign in again. See [reviewing](reviewing.md#approvals-given-in-skein-serve-or-on-the-forge).

## On the static site

The site `skein render --format html` writes can edit too, with no server at all: skein built for WebAssembly runs in the page.

```text
$ zig build wasm                     # or take skein-vVERSION-wasm32-wasi.wasm from a release
$ skein render --format html --edit --wasm zig-out/web/skein.wasm --out site
skein: 40 pages rendered to site
skein: the pages edit 39 files (649.7 KB, in _skein/files.json), with skein for WebAssembly
```

The site then carries, under `_skein/`, the WebAssembly module, the project's text files that `check` reads (its configuration, its documents' Markdown, the files its citation sets read, its results; not the rest of the repository), and the scripts that run skein over them in the page. Each page offers the same **Edit this file**, **edit** by each item, and **New item** as `skein serve`'s. The problems are checked as you type, by skein in the page.

A save is kept in the browser, not on the server that serves the files. A box at the bottom left lists the changed files, each a link to download it, and **Discard them** forgets them. The pages are not rendered again, so a page shows the files as they were rendered.

### Saving through the forge

Where the project names its forge (`[forge]`), the box also offers to save the changes there, through the forge's API, as the person editing:

| `[serve] save` | The changes go |
| --- | --- |
| `pull-request` (the default), `branch` | into a change, a branch `edit/NAME` from the branch changes go to, proposed in a pull request (a merge request on GitLab) |
| `commit` | in a commit on the branch changes go to |

The branch changes go to is `[serve] branch`, else the branch checked out when the site was rendered, else the repository's default. A project below the repository's top is saved at its place in it.

The page asks for a token the first time, and keeps it for the browser's session only:

| Forge | Token |
| --- | --- |
| GitHub | A fine-grained personal access token for the repository, with Contents and Pull requests, read and write. GitHub's sign-in cannot be done from a page alone: its token endpoints answer no other site. |
| GitLab | A personal access token with the `api` scope. |
| Forgejo | An access token with `write:repository`. |

Once saved, the changes are forgotten in the browser, and the page offers to open the pull request or the commit.

The module is about 9 MB (under 3 MB compressed, as web servers send it). The project's files are as large as they are.

## Who can reach it

By default `skein serve` answers only on this computer (127.0.0.1, `--port N` for another port than 8080), and only for requests addressed to `127.0.0.1` or `localhost`. A change is written only for a request that carries skein's own header, which a page of another site cannot send. There is no sign-in: anyone who can use the computer can use it, as they can the files.

## For a team

On a shared server, people sign in, and no forge is needed:

```text
skein serve --listen 0.0.0.0 --url https://reqs.example.com --sign-in proxy --proxy 10.0.0.2
```

| Option | What it does |
| --- | --- |
| `--listen ADDR` | The address it listens on; one other than this computer's own needs `--sign-in` and `--url`. |
| `--url URL` | The address people reach it at, behind the proxy: requests for that host are answered, and the forge sends people back to it. |
| `--sign-in proxy` | A reverse proxy in front (one that signs people in to the organization's single sign-on, such as oauth2-proxy) names the person in a header, `X-Forwarded-User` (`--user-header`), with their email in `X-Forwarded-Email` (`--email-header`). The header is believed only from the proxy's addresses, `--proxy IP`, by default this computer's. The proxy also gives HTTPS, which `skein serve` does not. |
| `--sign-in forge` | People sign in with the project's forge (`[forge]`): GitHub, GitLab or Forgejo, through an OAuth app made there, whose callback is `URL/_skein/oauth`. Its id and secret are in `SKEIN_OAUTH_CLIENT_ID` and `SKEIN_OAUTH_CLIENT_SECRET`. A session ends when it has not been used for 12 hours, and 7 days after its sign-in (`--session-hours N` and `--session-days N` give others); then the person signs in again. |
| `--sign-in oidc --issuer URL` | People sign in with an OpenID Connect provider: an organization's single sign-on, or GitLab. Its discovery document gives the rest, and the app's id and secret are in the same variables. It can be asked to make the person sign in again, for an approval that must be signed. Its sessions end as those of `--sign-in forge` do. |

SAML single sign-on is reached through one of these rather than by `skein serve` itself: an identity service that speaks both (Keycloak, Okta, Entra ID and most others) serves `--sign-in oidc` and passes a sign-in again on to the SAML provider as its `ForceAuthn`; or a reverse proxy that speaks SAML (Shibboleth's, `mod_auth_mellon`) serves `--sign-in proxy`, without a sign-in again for approvals. Reading SAML's assertions in `skein serve` would mean verifying XML signatures itself, which these leave to software made for it.

Anyone who reaches the server reads the pages; changing or approving anything needs someone signed in (emanspeaks, 2026-11-27), and the pages offer to sign in when nobody is. Each person has their own open change, in its own worktree, and their commits and approvals carry their name: the forge's login, or the proxy's header. Whose approval counts is the type's `approvers`, by those names. The checkout the server serves from is its own: clone the repository for it, and let the server's pushes and pulls keep it and its upstream together.
