# Writing items

An item is a piece of Markdown with an ID. It is either a paragraph or a list entry in a document, made an item by a marker, or a file of its own, with front matter.

## Items in documents: the marker

In a document, a marker at the start of a paragraph or of a list entry makes it an item. The text follows on the same line, or starts on the next:

```markdown
%rule[lex.comment.line legality] A line comment starts with `//` and ends at the end of the line.

%rule[lex.comment.block legality]
A block comment starts with `/*` and ends with the next `*/`.

Text without a marker is narrative: it explains, and is not an item.

1. %rule[lex.space syntax] White space separates tokens.
2. %rule[lex.tab syntax] A tab is white space.
```

The marker is a percent sign, the item type, and in brackets the ID and then optional words:

```text
%rule[expr.as.narrow legality final stage=s0 verifies=lex.token,lex.space note="two words"]
```

| Part | Meaning |
| --- | --- |
| `%rule` | The item type, one of the project's (`.skein/types/`). |
| `expr.as.narrow` | The ID, the first word in the brackets: letters, digits, `.`, `-` and `_`. |
| a bare word | The category or the status, whichever of the type's it is; at most one of each. |
| `key=value` | An attribute, the verification method, or links of the type `key`. Several values are separated by commas; a value with spaces is put in double quotes. |

A marker is recognized only at the start of a paragraph or of a list entry, as a percent sign, a lowercase name and an opening bracket. Anywhere else in a line, and inside a code block, the same characters are text. A marker that names an item type the project does not have is reported, so a misspelled type is not silently treated as prose.

The marker reads as plain text wherever Markdown is shown without skein, and `grep '%rule\['` finds every rule.

**The text of an item** is the rest of the paragraph or list entry that the marker is in. When the marker is alone on its line, it is the block after the marker: a paragraph, a list, a code block, a table or a quote. In both cases the lists, code blocks, tables and quotes that follow directly are included. So a paragraph that ends in a colon keeps its list, and the next paragraph is narrative again unless it has its own marker.

**A removed item** is its marker alone, with the status its type uses for removed items. Its ID stays taken, so it cannot be given to another item by mistake, and nothing may link or refer to it:

```markdown
%rule[lex.comment.nested removed]
```

## Parts: items inside an item

When an entry of an item's list has a marker of its own, it is a **part** of that item: an item itself, which can be linked to, cited and approved alone.

```markdown
%rule[lex.keywords syntax] The keywords are:

- %rule[.as syntax] `as`, which converts a value.
- %rule[.fn syntax] `fn`, which starts a function.
- and no others.
```

This is three items: `lex.keywords`, and its parts `lex.keywords.as` and `lex.keywords.fn`. Parts can have parts, to any depth.

- **Names:** an ID that starts with a dot extends the ID of the containing item, as above. An ID without the dot is used as written, so a part does not have to be named after the item that contains it. The dot form needs hierarchical IDs (IDs joined by dots) for both the part and the containing item.
- **Text:** the text of a part belongs to the part only. The own text of the containing item is the rest: here, the first line and the last entry.
- **Content:** the content of the containing item includes the content of its parts. A change to a part is also a change to the containing item (see [Fingerprints](reviewing.md#fingerprints)), and `skein diff` lists both.
- **Coverage:** an item with parts counts as linked to, or cited, when it has such a link or citation itself, or when every one of its parts does (`skein coverage`). Removed parts are not counted.

A list in which no entry has a marker is simply part of the text of the item. A list that does not follow an item can contain items too, as in the first example; those items are not parts of anything.

## Item files: front matter

A file that is one item starts with TOML between two `+++` lines:

```markdown
+++
id = "SRS-012"
type = "srs"
status = "approved"
priority = "high"
derives-from = ["SYS-003"]
+++

The software shall record the time of each measurement.
```

The rest of the file is the text of the item. A Markdown file in the directory that does not start with front matter is not an item, and is skipped: a readme, notes.

| Key | Meaning |
| --- | --- |
| `id` | The ID. Needed. |
| `type` | The item type; may be left out where the source in `.skein/config.toml` gives one. |
| `status`, `category`, `verification` | As their names say; each must be allowed by the item type. |
| the name of a link type | The IDs the item links to: a string, or an array of strings. |
| any other key | An attribute of the item type. |

## What the words mean

The same keys work in a marker and in front matter:

- `status`: one of the item type's statuses. An item that gives none has the first.
- `category`: one of the item type's categories (in a marker, the bare word). Needed when the type has categories.
- `verification`: how the item is verified, one of the methods the item type allows.
- the name of a link type (`.skein/links/`): the IDs the item links to.
- anything else: an attribute, which the item type must declare.

## References in text

Text refers to an item with a marker that has no item type: `%[id]` names an item where `%type[id]` declares one. Words after the ID are shown in its place when the ID itself should not appear:

```markdown
A line comment is not a %[lex.token]; see %[lex.space white space].
```

References work in narrative text as well as in items, so the introduction of a chapter, a heading or another document can point at a rule. `skein check` applies the same rules to them, and `skein trace` lists them under "Mentioned in". A reference inside an item is part of the content of that item. A reference in narrative text does not belong to any item, so it is not part of any fingerprint and does not make any link suspect.

Nothing inside a code span or a code block is a reference, nor is a percent sign that follows a letter or a digit (`50%[1]`). The double brackets of wikis and site generators (`[[a page]]`) mean nothing to skein, so a document can use both. `skein check` reports a reference to an item that does not exist or is removed. A reference with a colon, `%[other:some.id]`, names an item of another repository, which the project declares: see [other repositories](repositories.md).

An item renamed with `skein move` can keep its former IDs, as `aliases=lex.token` in its marker or `aliases = ["SRS-001"]` in its front matter. A reference, link or citation that uses a former ID still finds the item, and `skein check` warns that its ID has changed. A former ID stays taken, as a removed item's does.

Inside code spans and code blocks nothing is a marker or a reference, so the examples on this page need nothing. To write one as plain text in running text, put a backslash before the percent sign: `\%rule[x]` and `\%[x]` are neither. Markdown itself reads `\%` as an escaped percent sign, so GitHub, site generators and skein's own rendering all show `%rule[x]` and `%[x]`.

## Tested examples

A specification's code examples can be items, which the project's own tests compile or run. An item type with an `[example]` table is a type of examples:

```toml
# .skein/types/example.toml
categories = ["accepts", "rejects"]

[example]
link = "shows"
extensions = { cesium = ".csm" }
```

An example is a fenced code block with the marker on its opening line, after the language, which renderers ignore:

````markdown
%rule[lex.comment syntax] A comment runs to the end of the line.

```cesium %example
// a comment
```

```cesium %example[.open rejects]
/* not closed
```
````

- **Inside an item,** an example is a part of it and shows it: the first above is `lex.comment.example-1`, the second `lex.comment.open`, and both have a `shows` link to `lex.comment`. So `skein coverage` counts the rules that have an example, when `shows` is expected.
- **Elsewhere,** an example needs an ID, and says what it shows: ```` ```cesium %example[ex.both shows=lex.comment shows=lex.token] ````. A key that takes several values may be given more than once.
- **Accepted or rejected:** an example with the category `rejects` (or the one `example.rejects` names) must be rejected; one without a category must be accepted.

`skein examples --out DIR` writes each example to a file and lists them in `examples.json`, for the project's test driver: see [commands](commands.md).

## Citations in code and tests

Code and tests are not items, but they say which items they implement or check, in a comment. The project names the comment's marker in `.skein/config.toml` (`[[citations]]`), and the rest of the line is IDs, separated by commas or spaces:

```zig
// spec: lex.comment.line, lex.comment.block
test "comments" {
```

```c
/* Implements SRS-012. */
```

A full stop after an ID ends the citation, so a sentence can follow. A word that is not an ID ends it too.

A directory can cite items for every file in it and below it, with a file named `.skein-cites`: IDs, one or several on a line, and `#` for comments.

```text
# every test in this directory checks these
lex.comment.line
lex.comment.block
```

`skein check` reports a citation of an item that does not exist, is removed, or is of a type its citations may not name.

## What `skein check` reports

- An ID used twice, or not spelled as its type's IDs are.
- An item type, category, status or verification method that the schema does not have; a missing category.
- A reference in text, of an item or narrative, to an item that does not exist or is removed.
- A link to an item that does not exist, is removed, or is of a type the link cannot point to; a link from a type that cannot have it; a required link that is missing.
- A reference in text to an item that does not exist or is removed.
- A marker with nothing after it, one that is not closed or names no item type, a part named with a leading dot where that cannot work, and an item file without front matter.
- A citation of an item that does not exist, is removed, or is of a type its citations may not name.

## How skein reads Markdown

skein reads only the block structure of a file, to place items: headings, paragraphs, lists, fenced and indented code, block quotes, tables, HTML blocks and thematic breaks. What a block contains is left alone until a document is rendered.
