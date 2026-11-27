# Charter

What this specification is for, and how it is kept.

## Purpose and scope

Say which language this specifies, which edition, and what it leaves to implementations.

## How it is written

Every rule is an item with an ID, `%rule[ID category]`, and a category: syntax (what is written), legality (what is allowed), static (what a program means before it runs) or dynamic (what it does as it runs). A rule refers to other rules and to terms with `see=`. Terms are defined once, as `%term[ID]`, and listed in the [glossary](glossary.md).

Examples under a rule show it and are tested: a fenced block with `%example` on its opening line, of the category `rejects` when a compiler is to refuse it. A rejected example may give the error it must be refused with, `error="..."`. `skein examples --out DIR` writes them for the test driver.

## Conformance

Conformance tests cite the rules they check in a comment, and `skein coverage` lists the rules no test or example reaches yet; the [coverage page](coverage.md) shows the same.
