# The requirements of Skein

What Skein is required to do, written in Skein's own format: each paragraph with a `%req[...]` marker is a requirement, and the rest is narrative. Skein's tests cite the requirements they check (`// req:` and the IDs, in the test files under `src/` and those of the VS Code extension), so that

```text
skein check
skein coverage --profile implemented
skein trace check.links
```

run in this repository say whether the requirements are well formed, which of them have a test, and where a given one is tested.

A requirement that names no status is implemented, and is cited by a test. One marked `planned` describes something `docs/design.md` commits Skein to that the code does not do yet; it is here so that the plan is traced too, and needs no test (one may already check the part that is built).

| Document | Requirements of |
| --- | --- |
| [principles](principles.md) | What holds for all of Skein. |
| [project](project.md) | The `.skein/` directory: configuration and schema. |
| [items](items.md) | How items, references and citations are written and read. |
| [checking](checking.md) | What `skein check` reports. |
| [reviewing](reviewing.md) | Fingerprints, reviewed links, approvals: in roles, in order, signed. |
| [views](views.md) | `trace`, `coverage`, `diff`, `impact`, `export`, `render`, `baseline`, and the web interface: `serve`, `api`, the static site's edit mode. |
| [editing](editing.md) | `move`, `new`, `link`, the language server `lsp`, and the VS Code extension. |
| [planning](planning.md) | Work items and their schedule. |
| [agents](agents.md) | The Model Context Protocol server `mcp`, and instructions for coding agents. |
| [repositories](repositories.md) | Other repositories, `pin`, and the state of the network. |
| [results](results.md) | Test results, and what they say of the items. |
| [forge](forge.md) | Issues and pull requests on the forge, the mirror, GitLab's requirements and Jama Connect. |
| [templates](templates.md) | Templates built into Skein. |
| [importing](importing.md) | `import doorstop`, `csv`, `reqif`, `jama`, `gitlab-requirements`. |
| [planned](planned.md) | What is to come. |

How these are written: one requirement, one paragraph, one marker. An ID says what the requirement is about and never changes. A requirement that is dropped keeps its marker, with the status `removed`. A change to a requirement is made by a pull request, and merging the pull request accepts the change.
