+++
document = "SW-CLASS"
revision = "Draft"
item = "PRD-31"
maturity = "P"
+++

# Software classification and safety-criticality

The record of each software system's class (%[SWE-020]) and safety-criticality (%[SWE-205]), kept as a software record (%[SWE-176]). The class is the template's `class` option, and safety-criticality its `safety-critical` option, in `.skein/config.toml`; a change of class is handled as %[SWE-021] says.

## Software and its class

| Software | Class | Reasons |
| --- | --- | --- |
| Rover drive software | C | It drives a rover prototype in field tests at a research facility on Earth: mission support and research facility software (NPR 7150.2D, Appendix D). It flies on no vehicle, carries no crew, and no mission depends on it. |

## Safety-criticality

Recorded in the [safety-critical software determination](safety-criticality.md) (SW-SCD): the drive software is not safety-critical, so `safety-critical = false`.

## Concurrence

Classified by the software lead; software assurance concurred on 2027-01-12.
