# Tutorial: a new project under NPR 7150.2D

This tutorial starts the software of a new project from Skein's `npr7150.2d` template and takes it to its software requirements review (SRR): classified, its safety-criticality determined, its requirements traced up to the system and down to design, code, tests and results, the first rows of its Requirements Mapping Matrix written, its plans at the maturity SRR expects, and its documents delivered. It takes about half an hour. The project it ends with is the [`npr7150.2d` example](examples.md), so every file below can be read there in full.

You need the `skein` program on your `PATH` (see the [quickstart](quickstart.md)) and git. Every command below was run as shown; your fingerprints, commits and dates will differ.

## The project

`rover`: the drive software of a rover prototype, driven in field tests at a research facility on Earth. It takes drive commands from a ground station over a radio link and sets the speed of the wheel motors. It is a new git repository, on GitHub.

## 1. Start from the template

`skein template show npr7150.2d` lists the template's options. The one with no default is `class`, the software class of NPR 7150.2D's Appendix D. Software for a research facility is class C. Give it to `init`:

```text
$ skein init --template npr7150.2d --option class=C
skein: a project in ., from the template npr7150.2d, with 29 documents to start from; 'skein check' checks it; AGENTS.md tells coding agents about Skein; .github/workflows/skein.yml checks them and collects them as PDFs
Still to do:
- Say where the tests and the code are (`[[citations]]` in `.skein/config.toml`, often there as comments to fill in), so that `skein coverage` counts what cites the requirements.
- Set `[maturity] milestone` to the review the project is at next, so that `skein check` holds the documents to the maturity it expects.
- Fill in the documents that are still the template's skeletons (29: docs/classification.md, docs/data-dictionary.md, docs/design.md, docs/estimates.md, docs/hazards.md, docs/index.md, ...), or remove those the project's tailoring leaves out.
$ skein check
skein: rover: no problems (848 items of 16 types, 11 link types, 2 profiles, 0 citations)
```

The "still to do" list is this tutorial's plan. What `init` wrote:

- `.skein/config.toml`: the template and its options. `class = "C"`; `safety-critical`, `program`, `models-and-simulations` and `crewed` at their defaults, each with a comment that says what it means and what it brings along. A space flight project would set `program = "space-flight"`, which brings NPR 7120.5F and NPR 7123.1D; a crewed one `crewed = true`, which brings the human-rating standards. None applies here.
- `docs/`: a skeleton of each document of the handbook's topics 5.01 to 5.24, with document control (`document = "SW-SRS"`, `revision`, its product and maturity), and, since NPR 7150.2D defers to NASA-STD-8739.8B for software assurance in classes A to E, that standard's documents too, among them the safety-critical software determination.
- `standards/`: the text of NPR 7150.2D, the handbook's reading of each requirement, and NASA-STD-8739.8B's tasks, as read-only items (`SWE-050`). Skein provides them and a `.gitignore` there keeps them out of git: never copy them into the repository.
- `AGENTS.md` for coding agents, and `.github/workflows/skein.yml`, which step 8 comes back to.

Most of the 848 items are the standards' requirements. The documents refer to them (`%[SWE-050]`), and the reference is a link on the rendered page.

## 2. Classification and safety-criticality

Two records come first, since the rest follows from them. `docs/classification.md` gives the class and the reasons (SWE-020):

```markdown
| Software | Class | Reasons |
| --- | --- | --- |
| Rover drive software | C | It drives a rover prototype in field tests at a research facility on Earth: mission support and research facility software (NPR 7150.2D, Appendix D). It flies on no vehicle, carries no crew, and no mission depends on it. |
```

`docs/safety-criticality.md` is the safety-critical software determination (SWE-205, with NASA-STD-8739.8B, section 4.2). Every project of class A to E has one, even when the answer is no: it goes through the standard's five criteria against the system's hazard analysis. Here every hazard is controlled by hardware the software cannot override (a mechanical speed governor and a hardware emergency stop), so the software meets none of them:

```markdown
| a. Causes or contributes to a system hazardous condition/event | No | Hazard analysis HA-R-01: the drive motors are limited by a mechanical governor to 0.6 m/s whatever the software commands. |
```

So `safety-critical` stays `false`, and `docs/hazards.md` says that no hazard has software in it. Had the answer been yes, `safety-critical = true` would add the requirements of safety-critical software (SWE-023, SWE-134, SWE-219, SWE-220) to what `skein coverage` expects, and each hazard would be an item that software requirements `address`.

## 3. Requirements, traced up

The software's requirements come from the rover's. Those belong to the rover's systems engineering and usually live in another repository; here they are in `docs/system-requirements.md`, as items of the template's type `system`:

```markdown
%system[SYS-001] The rover shall come to rest when it loses its link to the ground station.
```

In `docs/srs.md`, the example requirement gives way to the software's own, each with its category, its verification method and the requirement it comes from:

```markdown
%requirement[SRS-001 functional verification=test derives=SYS-001] The software shall command zero speed within 2 seconds of receiving the last valid drive command.

%requirement[SRS-002 functional verification=test derives=SYS-002] The software shall not command a speed above 0.5 meters per second.
```

Two more, an interface requirement and one verified by inspection, are in the example's `docs/srs.md`. Coverage now says that every system requirement is traced to the software, and what is not yet traced down:

```text
$ skein coverage
...
derives links to system items: 3 of 3 (100%)
...
satisfies links to requirement items: 0 of 4 (0%)
  functional: 0 of 2 (0%)
  interface: 0 of 1 (0%)
  quality: 0 of 1 (0%)
...
```

These are the traces of SWE-052 that a class C project keeps: the `class` option chose them.

## 4. Design and code

Each component of `docs/design.md` is a `design` item that `satisfies` the requirements it meets:

```markdown
%design[DES-001 satisfies=SRS-001 satisfies=SRS-003] Link monitor (`src/link.c`): decodes each drive command from the radio, and reports the link lost when no valid command has come for 2 seconds.
```

The code says which component it implements, in a comment. The configuration has the citation sets for this as comments; remove the `#`s, and make the code's citations expected, so that `skein coverage` lists a component no code implements:

```toml
[[citations]]
name = "test"
path = "tests"
files = [".c"]
marker = "// verifies:"
to = ["requirement"]

[[citations]]
name = "code"
path = "src"
files = [".c"]
marker = "// implements:"
to = ["design"]
expected = true
```

```c
// Link monitor: decodes drive commands, and reports the link lost.
// implements: DES-001
```

```text
$ skein coverage
...
satisfies links to requirement items: 4 of 4 (100%)
...
code citations of design items: 3 of 3 (100%)
```

## 5. Verification and results

Test procedures are `procedure` items that `verify` requirements: one for the unit tests, run on every change, and two carried out on the rover's stand.

```markdown
%procedure[TST-003 unit verifies=SRS-001 verifies=SRS-002 verifies=SRS-003] Build and run the unit tests of `tests/` on the host: it passes when every test passes.

%procedure[TST-001 system verifies=SRS-001] Drive the wheels at 0.3 m/s, switch off the ground station's radio, and time the wheels to a stop: it passes when they stop within 2 seconds.
```

The unit tests cite the requirements they check (`// verifies: SRS-001`), as the first citation set says. Every requirement is now verified by something, but none is verified as its method requires until there are results:

```text
$ skein coverage
...
verifies links to requirement items: 4 of 4 (100%)
...
verified as their method requires:
  test: 0 of 3 (0%)
    not verified:
      SRS-001
      SRS-002
      SRS-003
  inspection: 0 of 1 (0%)
    not verified:
      SRS-004
```

A test run's results go in a file the project keeps, for the test report. Name the place in the configuration:

```toml
# the results of the test runs, for the test report
[results]
paths = ["verification/results"]
```

and write the run there, `verification/results/2027-02-03.toml` (a test driver can write it, or JUnit XML; see [test results](results.md)):

```toml
[[result]]
test = "link lost after two seconds"
file = "tests/test_link.c"
result = "pass"
implementation = "rover"
version = "0.1.0"

[[result]]
item = "TST-001"
result = "pass"
implementation = "rover"
version = "0.1.0"
note = "Wheels stopped 1.8 s after the radio was switched off."
```

```text
$ skein coverage
...
verified as their method requires:
  test: 3 of 3 (100%)
  inspection: 0 of 1 (0%)
    not verified:
      SRS-004
```

`SRS-004` waits for `TST-002`, the inspection of the log, to be carried out. `skein trace` shows a requirement with everything around it:

```text
$ skein trace SRS-001
SRS-001  (requirement, functional, draft)
  docs/srs.md:18
  fingerprint e8a7600fe4070e4fe09fe4b9ba4865e8
  verification = test

Links to:
  derives SYS-001 (system)

Linked from:
  satisfies DES-001 (design)
  verifies TST-003 (procedure)
  verifies TST-001 (procedure)

Cited by:
  test  tests/test_link.c:4

Above (all it rests on): SYS-001

Below (all that rests on it): DES-001, TST-003, TST-001

Results:
  rover 0.1.0: passed
    pass  link lost after two seconds  (verification/results/2027-02-03.toml, result 1)
    pass  TST-001  (verification/results/2027-02-03.toml, result 3)
```

`docs/traceability.md` and `docs/hazards.md` need no writing: they are generated from these links (`matrix satisfies`, `matrix verifies`), both ways, whenever the project is rendered.

## 6. The Requirements Mapping Matrix

The matrix says how the project meets each requirement its class invokes (SWE-125). A row is a `compliance` item in `docs/rmm.md`, FC, T, PC, NC or NA, linked to the requirement by `complies`, with its evidence:

```markdown
%compliance[rmm.swe-020 FC complies=SWE-020 evidence="SW-CLASS"] The software is classified as class C, with software assurance's concurrence.

%compliance[rmm.swe-205 FC complies=SWE-205 evidence="SW-SCD"] The software was determined not safety-critical with the facility's safety officer.
```

```text
$ skein coverage
...
complies links to swe items: 6 of 88 (6%)
  without:
    SWE-033
    SWE-024
    ...
```

Class C invokes 88 of the NPR's requirements, and the list is what is left to account for. A requirement the project is relieved of gets a `tailoring` item (`tailors=SWE-...`), in force once the Technical Authorities approve it (`skein approve --as ROLE`). Software assurance keeps its own matrix of NASA-STD-8739.8B's tasks for the same requirements (`docs/sa-rmm.md`; the `performs` line of coverage).

## 7. Ready for SRR

The handbook expects each document at a maturity at each review (topic 7.08): draft, preliminary, baselined, updated, final. Tell Skein which review is next:

```toml
[maturity]
order = ["D", "P", "B", "U", "F"]
milestone = "srr"
```

```text
$ skein check
docs/estimates.md:1:1: warning: document SW-EST is at D; at srr, PRD-03 is expected to be at P
docs/risks.md:1:1: warning: document SW-RISK is at D; at srr, PRD-21 is expected to be at U
docs/scmp.md:1:1: warning: document SW-SCMP is at D; at srr, PRD-05 is expected to be at P
docs/sdp.md:1:1: warning: document SW-SDP is at D; at srr, PRD-01 is expected to be at P
docs/traceability.md:1:1: warning: document SW-RTM is at D; at srr, PRD-12 is expected to be at P
skein: rover: no problems, 5 warnings (865 items of 16 types, 11 link types, 2 profiles, 6 citations)
```

Those are the plans still to write: the development plan, configuration management, the estimates and the risks (see them in the example). Each document's front matter says its maturity, raised as it is written (`maturity = "P"`):

```text
$ skein check
skein: rover: no problems (865 items of 16 types, 11 link types, 2 profiles, 6 citations)
```

The documents the project does not need yet (the user manual, the version description, the test report) stay skeletons until their review.

## 8. Deliver, and keep it checked

`skein render --format html --out site` makes the whole project a site to read, and the controlled documents (each with a `document` and a `revision`) are what a review receives:

```text
$ skein render --format document --controlled --out delivered
skein: 28 documents rendered to delivered
```

Each is one HTML file named by its ID and revision, `SW-SRS-Draft.html`, ready to print as PDF, and `documents.tsv` lists them. On GitHub there is nothing to do: the workflow `init` wrote does this on every push and pull request, prints each document to PDF, and keeps them, with the coverage, as `engineering-docs.zip`, an artifact of the run; and it fails the run when `skein check` finds a problem.

Commit, and mark what went to the review as a baseline, a git tag:

```text
$ git add -A && git commit -m "Rover software at SRR"
$ skein baseline srr
skein: baseline srr at 1a979ef; share it with: git push origin srr
```

After the review, a change shows what it reaches. Make the speed limit 0.4 m/s in `SRS-002`:

```text
$ skein impact
Impact of the changes from HEAD to the working tree

Changed (1):
  SRS-002  (requirement)  content  docs/srs.md:20

Look again at (2):
  DES-002  (design)  rests on SRS-002  docs/design.md:24
  TST-003  (procedure)  rests on SRS-002  docs/test-procedures.md:20

Cited in (1):
  tests/test_speed.c:4  (test)  SRS-002
$ skein diff srr
Changes from srr to the working tree

Changed (1):
  SRS-002  (requirement)  content  docs/srs.md:20
```

The design, the procedure and the test that rest on it are the ones to look at again, and `skein diff` gives the changes since the review, for the next one.

## Where next

- [Templates](templates.md): every option of `npr7150.2d`, and what it brings along.
- [Reviewing](reviewing.md): approvals by role, for tailoring and for the documents.
- [Test results](results.md): JUnit XML and TAP from the test runner.
- [Other repositories](repositories.md): system requirements and hazards kept by another repository, referred to across.
