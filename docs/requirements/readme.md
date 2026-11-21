# The requirements of skein

What skein is required to do, written in skein's own format: each paragraph under a `req[...]` marker is a requirement, and the rest is narrative. skein's tests cite the requirements they check (`// req:` and the IDs, in the test files under `src/`), so that

```text
skein check
skein coverage --profile implemented
skein trace check.links
```

run in this repository say whether the requirements are well formed, which of them have a test, and where a given one is tested.

A requirement that names no status is implemented. One marked `status=planned` describes what `docs/design.md` commits skein to and the code does not do yet; it is here so that the plan is traced too, and it has no test.

| Document | Requirements of |
| --- | --- |
| [principles](principles.md) | What holds for all of skein. |
| [project](project.md) | The `.skein/` directory: configuration and schema. |
| [items](items.md) | How items, references and citations are written and read. |
| [checking](checking.md) | What `skein check` reports. |
| [reviewing](reviewing.md) | Fingerprints, reviewed links, approvals. |
| [views](views.md) | `trace`, `coverage`, `diff`, `impact`, `export`. |
| [importing](importing.md) | `import doorstop`, `import csv`. |
| [planned](planned.md) | What is to come. |

How these are written: one requirement, one paragraph, one marker. An ID says what the requirement is about and never changes; a requirement that goes away keeps its marker, with `status=removed`. A change to a requirement is a pull request, and merging it is accepting it.
