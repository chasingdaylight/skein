+++
document = "SW-SDP"
revision = "Draft"
item = "PRD-01"
maturity = "P"
+++

# Software development and management plan

The plans of the software (%[SWE-013]), started as soon as the scope is known and complete by the end of requirements analysis (handbook topic 5.08). For a project this small it also holds the assurance and maintenance plans, and points to the configuration management plan.

## Organization and authority

A software lead and two developers, in the facility's robotics group; software assurance from the facility's SMA office. The software lead decides the software's design; the test director decides when the rover drives.

## Classification and tailoring

The drive software is class C and not safety-critical ([classification](classification.md)); the tailored [Requirements Mapping Matrix](rmm.md) goes to the Technical Authorities for approval at SRR.

## Engineering environment

C with the controller vendor's compiler; the unit tests build and run on the developers' machines and in CI; the requirements, design and test documents are kept with the code, in git, and checked by Skein.

## Work breakdown, cost and schedule

The [estimates](estimates.md) (%[SWE-015], %[SWE-016], %[SWE-033]); actuals are tracked against them at each review (%[SWE-024]).

## Life cycle and milestones

Incremental: one release before each field test. Reviews (%[SWE-037]): SRR, then a combined design and test readiness review before the first field test.

## Verification and validation

Peer review of every change before it is merged; unit tests in CI on every change; the [test procedures](test-procedures.md) on the rover's stand before each field test. Records are the pull requests, the CI runs and the [test report](test-report.md).

## Quality, safety, security and privacy

Not safety-critical ([determination](safety-criticality.md)). The radio link is the facility's closed network (%[SWE-156]). No off-the-shelf software but the vendor's runtime library (%[SWE-027]).

## Suppliers

None (%[SWE-039], %[SWE-040], %[SWE-042] do not apply).

## Configuration management, peer reviews and metrics

[Configuration management](scmp.md); peer reviews are the pull request reviews ([peer reviews](peer-reviews.md)); [metrics](metrics.md) are the coverage and the test results Skein reports.

## Risk management and training

[Risks](risks.md); the developers know C and the controller, and need no training (%[SWE-017]).
