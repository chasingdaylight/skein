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

## When the file changed meanwhile

A page remembers the file as it read it. If the file changed since (someone saved it in an editor, or a pull brought a change), **Save** writes nothing and says so: copy your change, close the box, and the page loads the file as it is now. While a box is open, the page does not load itself again, so nothing you typed is lost.

## Who can reach it

`skein serve` answers only on this computer (127.0.0.1, `--port N` for another port than 8080), and only for requests addressed to `127.0.0.1` or `localhost`. A change is written only for a request that carries skein's own header, which a page of another site cannot send. There is no sign-in: anyone who can use the computer can use it, as they can the files.
