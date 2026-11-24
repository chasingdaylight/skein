+++
document = "AI-INVENTORY"
revision = "Draft"
+++

# AI inventory

The AI systems the project develops, acquires or uses, each an item of the type `ai-system` (`AIS-001` and on), after %[govern.1.6]: what it is for (%[map.1.1]), what kind of system it is, whether a third party supplies it (%[govern.6.1]), and the risk tier the organization gives it against its risk tolerance (%[map.1.5]). A system exposed to a risk of generative AI (NIST AI 600-1) links to it with `exposed-to`.

%ai-system[AIS-001 planned ai_kind=generative third_party=yes risk_tier=moderate purpose="Summarize anomaly reports for the review board" exposed-to=gen-ai.confabulation,gen-ai.information-security] The summarizer of anomaly reports. (An example: replace it.)

```skein
list ai-system columns=status,ai_kind,third_party,risk_tier,purpose
```

## Decommissioning

How each system is retired without raising risk or lowering the organization's trustworthiness (%[govern.1.7]); a retired system keeps its item, with the status `retired`.
