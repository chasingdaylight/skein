# Example: a language specification

A specification written as a document: paragraphs with markers are rules and terms, the rest is narrative. Tests cite the rules they check.

Try, from this directory:

```text
skein check
skein trace expr.binary.syntax
skein coverage
skein coverage --profile core
skein export links
```

`skein coverage` shows that the rules of the `full` stage have no tests yet, and `--profile core` that the `core` stage is covered.

| File | What it shows |
| --- | --- |
| `.skein/config.toml` | The source, and the citation set for the tests. |
| `.skein/types/rule.toml` | Categories, and a required attribute that is part of a rule's fingerprint. |
| `.skein/profiles/core.toml` | A profile: the rules of one stage. |
| `spec/expressions.md` | Markers, narrative text, a rule with a list and one with a code block, references in text, a removed rule. |
| `tests/` | Citations: `# spec:` and the IDs. |
