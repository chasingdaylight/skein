# Example: a language specification, from the `langspec` template

The specification of calc, a small calculator language, written as documents: paragraphs with markers are rules and terms, code blocks marked `%example` are tested examples, and the rest is narrative. Tests cite the rules they check. It uses Skein's [`langspec` template](../../docs/templates.md), with one change of its own: its rules have a `stage`, `core` or `full`.

Try, from this directory:

```text
skein check
skein trace expr.binary.syntax
skein coverage
skein coverage --profile core
skein examples --out examples
skein render --format html --out site
```

`skein coverage` shows that the rules of the `full` stage have no tests yet, and `--profile core` that the `core` stage is covered by both examples and tests. `skein examples` writes each example to a file, with `examples.json`, which says which must be accepted and which rejected, with what error: what a test driver needs.

| File | What it shows |
| --- | --- |
| `.skein/config.toml` | The template, the source, and the citation set for the tests. |
| `.skein/types/rule.toml` | A type of the project's own replacing the template's: its categories, and a required attribute that is part of a rule's fingerprint. |
| `.skein/profiles/core.toml` | A profile: the rules of one stage. |
| `spec/charter.md` | The template's charter, filled in. |
| `spec/expressions.md` | Rules and terms, narrative text, a rule with a list and one with a grammar, references in text, examples accepted and rejected with the error they must give, a conformance test carried out by hand, a removed rule. |
| `spec/glossary.md`, `spec/coverage.md` | Pages generated from the items: the terms, and the coverage with a matrix of the examples of each rule. |
| `tests/` | Citations: `# spec:` and the IDs. |
