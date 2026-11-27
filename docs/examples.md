# Examples

Small projects to read and copy from, each in `examples/` of Skein's repository. Each one is checked by Skein's own tests on every change, so it works with this release, and each is rendered here as `skein render --format html` makes it.

| Example | What it is | Rendered |
| --- | --- | --- |
| [`npr7150.2d`](https://github.com/chasingdaylight/skein/tree/main/examples/npr7150.2d) | Software under NASA's NPR 7150.2D, from the `npr7150.2d` template: a rover's drive software, class C, at its requirements review, with its classification, safety-criticality determination, requirements, design, code, tests, test results, plans and the first rows of its mapping matrix. The [tutorial](tutorial-npr7150.md) builds it. | [site](examples/npr7150.2d/index.html) |
| [`langspec`](https://github.com/chasingdaylight/skein/tree/main/examples/langspec) | A language specification, from the `langspec` template: rules and terms, tested examples accepted and rejected, conformance tests, a profile for a stage of the language, and a type of the project's own replacing the template's. | [site](examples/langspec/index.html) |
| [`requirements`](https://github.com/chasingdaylight/skein/tree/main/examples/requirements) | Requirements each a file of its own, with types written by hand: system and software requirements, a test procedure, review records and an approval. | [site](examples/requirements/index.html) |

Each example's readme lists the commands to try in it and what each of its files shows. To try one, clone the repository and run `skein check` and `skein coverage` in its directory.
