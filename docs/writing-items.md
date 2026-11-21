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

## How skein reads Markdown

skein reads only the block structure of a file, to place items: headings, paragraphs, lists, fenced and indented code, block quotes, tables, HTML blocks and thematic breaks. What a block contains is left alone until a document is rendered.
