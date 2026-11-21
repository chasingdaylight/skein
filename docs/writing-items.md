# Writing items

An item is a piece of Markdown with an ID. It is either a paragraph in a document, made an item by a marker line, or a file of its own, with front matter.

## Paragraph items: the marker line

In a document, a marker line makes the block after it an item:

```markdown
rule[lex.comment.line] legality
A line comment starts with `//` and ends at the end of the line.

Text without a marker is narrative: it explains, and is not an item.
```

The marker is a line of its own that starts at the left margin: the item type, the ID in brackets, then optional words.

```text
rule[expr.as.narrow] legality stage=s0 verifies=lex.token,lex.space note="two words"
```

| Part | Meaning |
| --- | --- |
| `rule` | The item type, one of the project's (`.skein/types/`). |
| `[expr.as.narrow]` | The ID: letters, digits, `.`, `-` and `_`. |
| a bare word | The category, at most one. |
| `key=value` | An attribute, the status, or links of the type `key`. Several values are separated by commas; a value with spaces is put in double quotes. |

A line is a marker only when it starts with the name of an item type, so prose such as `array[i] is the element` stays prose. Inside a code block nothing is a marker.

The marker reads as plain text wherever Markdown is shown without skein, and `grep '^rule\['` finds every rule.

**What the item's text is:** the block after the marker (a paragraph, a list, a code block, a table or a quote), with the lists, code blocks, tables and quotes that follow it directly. So a paragraph that ends in a colon keeps its list, and the next paragraph is narrative again unless it has a marker of its own.

**A removed item** is its marker alone, with the status its type uses for removed items. Its ID stays taken, so it cannot be given to another item by mistake, and nothing may link or refer to it:

```markdown
rule[lex.comment.nested] status=removed
```

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

The rest of the file is the item's text.

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

Text refers to an item by its ID in double brackets, with the words to show after a bar when the ID itself should not appear:

```markdown
A line comment is not a [[lex.token]]; see [[lex.space|white space]].
```

Nothing inside a code span or a code block is a reference. `skein check` reports a reference to an item that does not exist or is removed. A reference with a colon, `[[other:some.id]]`, names an item of another repository; those are not checked yet.

## What `skein check` reports

- An ID used twice, or not spelled as its type's IDs are.
- An item type, category, status or verification method that the schema does not have; a missing category.
- An attribute the type does not declare, of the wrong kind, or with a value that is not allowed; a required attribute that is missing.
- A link to an item that does not exist, is removed, or is of a type the link cannot point to; a link from a type that cannot have it; a required link that is missing.
- A reference in text to an item that does not exist or is removed.
- A marker with nothing after it, and an item file without front matter.

## How skein reads Markdown

skein reads only the block structure of a file, to place items: headings, paragraphs, lists, fenced and indented code, block quotes, tables, HTML blocks and thematic breaks. What a block contains is left alone until a document is rendered.
