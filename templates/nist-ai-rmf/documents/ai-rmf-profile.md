+++
document = "AI-RMF-PROFILE"
revision = "Draft"
+++

# AI RMF profile

How each AI system in scope addresses each subcategory of the AI RMF core: its current profile. A row is an item of the type `ai-rmf-record`, linked by `ai-rmf-addresses` to the subcategory, with the system it is for, its category (FC fully addressed, T tailored, PC partially, NC not addressed, NA not applicable), and the record that shows it; a subcategory not fully addressed has its rationale. The target profile is the same table with the outcomes the organization wants.

```text
%ai-rmf-record[rec.ais-001.govern.1.6 FC ai-rmf-addresses=govern.1.6 system=AIS-001 evidence="AI inventory"] The system is in the inventory.
```

```skein
matrix ai-rmf-addresses columns=function,group from.columns=system,category,evidence
```

```skein
coverage
```
