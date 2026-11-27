# Charter

What this specification is for, and how it is kept.

## Purpose and scope

This specifies calc, a calculator language: numbers, the four arithmetic operators and powers, evaluated to a number. It is in two stages: `core`, what the first implementation must do, and `full`, which adds powers. How an implementation prints a value is left to it.

## How it is written

Every rule is an item with an ID, `%rule[ID category stage=STAGE]`, and a category: syntax (what is written), legality (what is allowed), static (what an expression means before it is evaluated) or dynamic (what evaluating it does). A rule refers to other rules and to terms with `see=` or a reference in its text. Terms are defined once, as `%term[ID]`, and listed in the [glossary](glossary.md).

Examples under a rule show it and are tested: a fenced block with `%example` on its opening line, of the category `rejects` when an implementation is to refuse it, with the error it must give. `skein examples --out DIR` writes them for the test driver.

## Conformance

The tests in `tests/` cite the rules they check (`# spec: ID`); a conformance test that is carried out by hand is an item, `%test[ID verifies=RULE]`. `skein coverage` lists the rules no test or example reaches yet, and the [coverage page](coverage.md) shows the same.
