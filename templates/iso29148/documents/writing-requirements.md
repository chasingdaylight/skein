# Writing requirements

A checklist, in skein's words, of what ISO/IEC/IEEE 29148:2018 asks of requirements; the standard itself is the authority, and its clauses are given for reference. Each requirement is an item: business (`BRS-001`), stakeholder (`STK-001`), system (`SYS-001`) or software (`SRS-001`), with `refines`, `derives` and `allocates` links between the levels and `verifies` from its verifications.

## Each requirement (clause 5.2.5)

- **Needed:** taking it out would leave a gap in what the system must do or be.
- **At its level:** it says what is needed, not how, at the level of the entity it is about.
- **Unambiguous:** it can be read one way only.
- **Complete:** nothing else is needed to understand it.
- **Singular:** it states one thing; two needs are two items.
- **Feasible:** it can be met within the constraints of cost, schedule and technology.
- **Verifiable:** there is a way to show it is met, and the item says which (`verification=`).
- **Correct and conforming:** it reflects the need it comes from, and follows the project's form for requirements.

## The set of requirements (clause 5.2.6)

The set is complete, consistent (no two contradict), feasible as a whole, understandable, and can be shown to meet the needs above it. `skein coverage` counts the needs that have no requirement under them, and the requirements without verification.

## Attributes (clause 5.2.8)

Besides its ID and text, a requirement may carry its priority, owner, source, rationale, risk, difficulty and acceptance criteria, which the template's types declare. Its version is its history in git; its status is its status in skein.

## Wording

Requirements use "shall"; statements of fact, "will"; goals, "should". Avoid terms that cannot be verified: "user-friendly", "fast", "as appropriate", "at least" without a figure.
