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

With a change, the bar at the bottom of each page says which change is checked out, and offers to merge, propose, leave or abandon it. With none, it lists the changes there are, and **Start a change** names a new one, in lowercase letters, digits and dashes (`fix-lexing`); a save when no change is checked out asks for its name. Each commit is the user's as git knows them (`git config user.name`). Without git, a save is written and not committed.

### What `check` warns of

A checkout cannot stop anyone from committing as they like, so Skein says when the chosen way was not followed, and refuses nothing (emanspeaks, 2026-11-27). From the commit that set `save` on, `skein check` warns of:

- with `commit` and `editors`: commits to the sources by anyone not listed;
- with `branch` or `pull-request`: commits straight on `branch` that were not merged from a change. A squashed pull request, whose subject ends in `(#12)`, counts as merged.

## When the file changed meanwhile

A page remembers the file as it read it. If the file changed since (someone saved it in an editor, or a pull brought a change), **Save** writes nothing and says so: copy your change, close the box, and the page loads the file as it is now. While a box is open, the page does not load itself again, so nothing you typed is lost.

## Who can reach it

`skein serve` answers only on this computer (127.0.0.1, `--port N` for another port than 8080), and only for requests addressed to `127.0.0.1` or `localhost`. A change is written only for a request that carries skein's own header, which a page of another site cannot send. There is no sign-in: anyone who can use the computer can use it, as they can the files.
