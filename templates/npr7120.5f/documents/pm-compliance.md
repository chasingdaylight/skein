+++
document = "PM-COMPLIANCE"
revision = "Draft"
+++

# NPR 7120.5F compliance matrix

How the project meets each requirement of NPR 7120.5F (its Table C-1, attached to the Formulation Agreement in Formulation and to the Project Plan in Implementation): a row is an item of the type `pm-compliance`, linked by `complies-pm`, FC, T or NA, with its justification. Tailoring is approved by those the requirement names (`approvers`), with the concurrence of its owner.

```text
%pm-compliance[compliance.pm-2.2.2 FC complies-pm=PM-2.2.2 evidence="Project Plan, section 2.2"] The work is organized by a product-based WBS.
```

```skein
matrix complies-pm columns=owner,approvers from.columns=category,evidence
```
