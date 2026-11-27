+++
document = "SW-SCMP"
revision = "Draft"
item = "PRD-05"
maturity = "P"
+++

# Software configuration management plan

How the software is kept under configuration management (%[SWE-079]), after handbook topic 5.06. With Skein, the items and documents are in git: baselines are its tags (`skein baseline`), and changes are its commits and pull requests.

## Organization and responsibilities

The software lead is the configuration manager; the facility's configuration management directive applies.

## Identification

The configuration items are the repository's directories: the code (`src/`), the tests (`tests/`), the documents (`docs/`) and the results (`verification/`) (%[SWE-081]). Releases are tagged `vMAJOR.MINOR.PATCH`.

## Change control

Every change is a pull request, reviewed by a developer who did not write it; one that changes a requirement is reviewed by the software lead too, and `skein check` marks the links it makes suspect (%[SWE-080], %[SWE-082]).

## Status accounting

git's history and the pull requests; `skein diff` between baselines (%[SWE-083]).

## Audits and reviews

Before each release, the software lead checks that the release's tag, its version description and its test results agree (%[SWE-084]).

## Release management and delivery

Each release is built by CI from its tag, described in the [version description](vdd.md), and loaded onto the rover by the test director (%[SWE-085]).

## Generated code

None (%[SWE-146], %[SWE-206] do not apply).

## Schedule, resources and upkeep of this plan

The software lead keeps this plan up to date at each review.
