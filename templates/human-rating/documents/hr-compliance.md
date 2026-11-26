+++
document = "HR-COMPLIANCE"
revision = "Draft"
+++

# Human-rating compliance matrix

How the system meets each requirement of NPR 8705.2C (`HRC-`) and of NASA-STD-8719.29 (`HR-`): a row is an item of the type `hr-compliance`, linked by `complies-hr`, of the category FC (fully compliant), T (tailored, by an approved waiver, deviation or exception: %[HRC-2.2.2]) or NA (not applicable), with its evidence. The certification package summarizes the tailoring at each review (%[HRC-2.2.7]).

```text
%hr-compliance[compliance.hr-4.3.1 FC complies-hr=HR-4.3.1 evidence="Integrated hazard analysis, section 3"] Single failure tolerance to catastrophic events, as the design and safety analyses set it.
```

```skein
matrix complies-hr columns=title from.columns=category,evidence
```

```skein
coverage
```
