+++
document = "IT-COMPLIANCE"
revision = "Draft"
+++

# NPR 7120.7A compliance matrix

How the service line or project meets each requirement of NPR 7120.7A (its Appendix C): a row is an item of the type `it-compliance`, linked by `complies-it` to the requirement, with its category (C comply, PC partially comply, NC not comply, NA not applicable) and the record that shows it. A row that is not C has its justification: why and how the requirement is tailored, and the name and date of the requirement owner in the Office of the Chief Information Officer who approved it in writing (%[IT-3.2.e]). The preliminary matrix is attached to the Organizational Summary or the Formulation Authorization Document (FAD) and the final one to the Service Line Plan or the Project Plan, and it becomes part of the scope baseline (%[IT-4.5.1.d], %[IT-5.4.2.3.a.4]).

```text
%it-compliance[compliance.it-3.9 C complies-it=IT-3.9 evidence="Project Plan, section 6"] Risk analyses are made in every phase, as the Risk Management Plan of the Office of the Chief Information Officer says.
```

```skein
matrix complies-it columns=scope from.columns=category,phase,evidence
```
