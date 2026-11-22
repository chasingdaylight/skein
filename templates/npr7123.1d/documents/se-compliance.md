+++
document = "SE-COMPLIANCE"
revision = "Draft"
+++

# NPR 7123.1D compliance matrix

How the project meets each requirement of NPR 7123.1D (its Appendix H): a row is an item of the type `se-compliance`, linked by `complies-se`, of the category FC (fully compliant), T (tailored) or NA (not applicable), with its justification. Tailoring is approved by the Engineering Technical Authority (%[SE-06]).

```text
%se-compliance[compliance.se-07 FC complies-se=SE-07 evidence="Systems engineering management plan, section 4.1"] The stakeholder expectations definition process is in the plan.
```

```skein
matrix complies-se columns=section from.columns=category,evidence
```
