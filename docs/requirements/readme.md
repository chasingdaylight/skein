# The requirements of skein

What skein is required to do, written in skein's own format: each paragraph with a `%req[...]` marker is a requirement, and the rest is narrative. skein's tests cite the requirements they check (`// req:` and the IDs, in the test files under `src/`), so that

```text
skein check
skein coverage --profile implemented
skein trace check.links
```

run in this repository say whether the requirements are well formed, which of them have a test, and where a given one is tested.

A requirement that names no status is implemented. One marked `planned` describes something `docs/design.md` commits skein to that the code does not do yet. It is here so that the plan is traced too, and it has no test.

| Document | Requirements of |
| --- | --- |
| [principles](principles.md) | What holds for all of skein. |
| [project](project.md) | The `.skein/` directory: configuration and schema. |
| [items](items.md) | How items, references and citations are written and read. |
| [checking](checking.md) | What `skein check` reports. |
| [reviewing](reviewing.md) | Fingerprints, reviewed links, approvals. |
| [views](views.md) | `trace`, `coverage`, `diff`, `impact`, `export`, `render`, `baseline`. |
| [editing](editing.md) | `move`, `new`, `link`, and the language server `lsp`. |
| [repositories](repositories.md) | Other repositories, `pin`, and the state of the network. |
| [results](results.md) | Test results, and what they say of the items. |
| [importing](importing.md) | `import doorstop`, `import csv`. |
| [planned](planned.md) | What is to come. |

How these are written: one requirement, one paragraph, one marker. An ID says what the requirement is about and never changes. A requirement that is dropped keeps its marker, with the status `removed`. A change to a requirement is made by a pull request, and merging the pull request accepts the change.
