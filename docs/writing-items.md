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

A marker is only a marker at the start of a paragraph or of a list entry: a percent sign, a lowercase name and an opening bracket. Elsewhere in a line, and inside a code block, it is text. A marker that names no item type of the project is reported, so a misspelled type is not passed over as prose.

The marker reads as plain text wherever Markdown is shown without skein, and `grep '%rule\['` finds every rule.

**What the item's text is:** the rest of the marker's paragraph or list entry (or, when the marker stands alone on its line, the block after it: a paragraph, a list, a code block, a table or a quote), with the lists, code blocks, tables and quotes that follow it directly. So a paragraph that ends in a colon keeps its list, and the next paragraph is narrative again unless it has a marker of its own.

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

- **Names:** an ID that starts with a dot continues the ID of the whole, as above. An ID without the dot is the ID as written, so a part need not be named after its whole. The dot is for types whose IDs are joined by dots, the whole's and the part's both.
- **Text:** a part's text is its own. The whole's own text is what is left: here the first line and the last entry.
- **What the whole says** includes what its parts say: a change to a part is a change to the whole (see [Fingerprints](reviewing.md#fingerprints)), and `skein diff` lists both.
- **Coverage:** a whole counts as linked to, or cited, when it is itself or when every one of its parts is (`skein coverage`). Removed parts do not count.

A list in which no entry has a marker is simply the item's text. A list that follows no item can hold items too, as in the first example; those are parts of nothing.

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

The rest of the file is the item's text. A Markdown file in the directory that does not start with front matter is not an item, and is passed over: a readme, notes.

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

Nothing inside a code span or a code block is a reference, nor is a percent sign that follows a letter or a digit (`50%[1]`). The double brackets of wikis and site generators (`[[a page]]`) mean nothing to skein, so a document can use both. `skein check` reports a reference to an item that does not exist or is removed. A reference with a colon, `%[other:some.id]`, names an item of another repository; those are not checked yet.

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
- An attribute the type does not declare, of the wrong kind, or with a value that is not allowed; a required attribute that is missing.
- A link to an item that does not exist, is removed, or is of a type the link cannot point to; a link from a type that cannot have it; a required link that is missing.
- A reference in text to an item that does not exist or is removed.
- A marker with nothing after it, one that is not closed or names no item type, a part named with a leading dot where that cannot work, and an item file without front matter.
- A citation of an item that does not exist, is removed, or is of a type its citations may not name.

## How skein reads Markdown

skein reads only the block structure of a file, to place items: headings, paragraphs, lists, fenced and indented code, block quotes, tables, HTML blocks and thematic breaks. What a block contains is left alone until a document is rendered.
