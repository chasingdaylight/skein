+++
document = "SW-CLASS"
revision = "Draft"
item = "PRD-31"
maturity = "D"
+++

# Software classification and safety-criticality

The record of each software system's class (%[SWE-020]) and safety-criticality (%[SWE-205]), kept as a software record (%[SWE-176]). The class is the template's `class` option, and safety-criticality its `safety-critical` option, in `.skein/config.toml`; a change of class is handled as %[SWE-021] says.

## Software and its class

For each system or subsystem with software: its name, its class (NPR 7150.2D, Appendix D), and the reasons, from the questions of the classification process.

## Safety-criticality

Recorded in the [safety-critical software determination](safety-criticality.md) (SW-SCD), which NASA-STD-8739.8B's template brings for classes A to E: for each software system, whether it is safety-critical by the criteria of NASA-STD-8739.8B, section 4.2, how that was determined with the safety and mission assurance organization, and the hazards it is part of. The `safety-critical` option follows it.

## Concurrence

Who classified it, and the independent assessment or concurrence of software assurance, with the date.
