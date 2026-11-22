+++
document = "MS-RIM"
revision = "Draft"
+++

# Requirements identification matrix

How each model in scope meets each requirement of NASA-STD-7009B (Appendix A of the standard). A row is an item of the type `ms-record`, linked by `meets` to the requirement, with the model it is for, its category (FC, T, PC, NC or NA), and the record that shows it; a requirement not met has its rationale.

```text
%ms-record[rim.mdl-001.ms-40 FC meets=MS-40 model=MDL-001 evidence="Model plan, section 1"] The intended use is recorded.
```

```skein
matrix meets columns=section from.columns=model,category,evidence
```
