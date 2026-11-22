# vendor

Code taken from other projects and built into skein. Each is copied in as it was published, with its license and its version, checked against what its publisher gives for it, and updated only by a reviewed change.

| Directory | What | License | Where it comes from | How it is updated |
| --- | --- | --- | --- | --- |
| `mermaid/` | mermaid's browser build, `mermaid.min.js`, which draws the ` ```mermaid ` diagrams of pages that `skein render --format html` or `--format document` writes | MIT (`mermaid/LICENSE`) | the npm package `mermaid`, its `dist/mermaid.min.js`, at the version in `mermaid/VERSION`, checked against the sha512 integrity hash the npm registry publishes for it | `tools/mermaid/fetch.sh [VERSION]`; the weekly `mermaid-updates` workflow opens a pull request into `main` when there is a newer release |
