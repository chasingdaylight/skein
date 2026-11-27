# Example: software under NPR 7150.2D, from the `npr7150.2d` template

The drive software of a rover prototype for field tests at a research facility: class C, not safety-critical, at its software requirements review (SRR). It was started with

```text
skein init --template npr7150.2d --option class=C
```

and then its documents were filled in as far as SRR needs: the [tutorial](../../docs/tutorial-npr7150.md) walks through each step.

Try, from this directory:

```text
skein check
skein coverage
skein trace SRS-001
skein render --format html --out site
skein render --format document --controlled --out delivered
```

`skein check` holds each document to the maturity the handbook expects at SRR. `skein coverage` shows what is done (every software requirement traced to the rover's requirements, to design and to verification, the design cited by the code, the test results in) and what is not: 82 of the 88 rows of the Requirements Mapping Matrix, software assurance's own matrix, and the inspection of `SRS-004`.

| File | What it shows |
| --- | --- |
| `.skein/config.toml` | The template with its options, the maturity milestone, citation sets for the tests and the code, and where the results are. |
| `docs/classification.md`, `docs/safety-criticality.md` | The class, and the safety-critical software determination that NASA-STD-8739.8B's template brings: not safety-critical, and why. |
| `docs/system-requirements.md`, `docs/srs.md` | The rover's requirements, and the software requirements that come from them (`derives`), each with its verification method. |
| `docs/design.md`, `src/` | Design components that satisfy the requirements, and the code that cites them (`// implements: DES-001`). |
| `docs/test-procedures.md`, `tests/` | Procedures that verify the requirements, and unit tests that cite them (`// verifies: SRS-001`). |
| `verification/results/` | A test run's results, for the test report. |
| `docs/rmm.md` | The first rows of the Requirements Mapping Matrix. |
| `docs/sdp.md`, `docs/scmp.md`, `docs/estimates.md`, `docs/risks.md` | The plans, at the maturity SRR expects. |
| `docs/traceability.md`, `docs/hazards.md` | Pages generated from the links: the traces of SWE-052. |

The other documents are still the template's skeletons, as a project at SRR has them. `standards/` is written by Skein, from the text it carries, and kept out of git.
