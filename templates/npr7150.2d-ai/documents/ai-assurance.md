+++
document = "AI-ASSURANCE"
revision = "Draft"
+++

# AI assurance

The minimum set of documents the handbook (topic 8.25, section 8) expects of a project that incorporates AI, with what each answers. See [the handbook's notes](../standards/npr7150.2d-ai/handbook-ai.md) and NASA's [principles](../standards/npr7150.2d-ai/ethics.md).

## Suitability assessment

Whether AI is the right approach, with the rationale (%[AIN-001], %[AIN-011]): rules that can be written down are not a case for AI; the error tolerance and interpretability the system needs; the principles it has to meet (%[ethic.fair], %[ethic.transparent], %[ethic.accountable], %[ethic.secure-safe], %[ethic.human-centric], %[ethic.robust]).

## Evaluation plan and benchmarks

Laboratory and production evaluation, with probabilistic acceptance criteria and human judgment where a result is ambiguous (%[AIN-013], %[AIN-017], %[AIN-023]).

## Data provenance and quality report

Origin, licensing and representativeness of every data set, drift detection and its thresholds, and how the data is kept (%[AIN-007], %[AIN-014], %[AIN-022]).

## AI safety case

Hazards, mitigations, the operating envelope, residual risk and the authority that approves it, reviewed at the key decision points (%[AIN-016]).

## Security threat model and red-team findings

The supply chain, the risks of generative AI, guardrails, and findings tracked to closure (%[AIN-010], %[AIN-015]).

## Architecture contracts and substitution plan

The interfaces between components and the plan to swap a model or provider (%[AIN-008], %[AIN-009], %[AIN-019], %[AIN-020]).

## Oversight and change

Who oversees the system and with what authority (%[AIN-018]), the risks it adds to the project's risk management (%[AIN-024]), and the cost and plan for continuous change (%[AIN-021]).
