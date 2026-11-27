+++
document = "SW-SCD"
revision = "Draft"
+++

# Safety-critical software determination

The determination, with the safety and mission assurance organization, of whether the project's software is safety-critical (SWE-205; %[SA-205]), by the criteria of section 4.2 of NASA-STD-8739.8B. It is made and recorded for every project, whatever its class: software found not safety-critical has this record, saying so and why, and nothing more is required of it for safety; software found safety-critical brings the safety tasks of the standard, and the template's `safety-critical` option is set to `true` in `.skein/config.toml`.

## Criteria

Software is safety-critical if it meets at least one of these (NASA-STD-8739.8B, section 4.2), as the hazard analysis shows:

| Criterion | Met? | Basis (hazard report, analysis) |
| --- | --- | --- |
| a. Causes or contributes to a system hazardous condition/event | No | Hazard analysis HA-R-01: the drive motors are limited by a mechanical governor to 0.6 m/s whatever the software commands. |
| b. Provides control or mitigation for a system hazardous condition/event | No | HA-R-01 credits only the hardware controls: the governor, and the radio-linked emergency stop that cuts motor power. |
| c. Controls safety-critical functions | No | The emergency stop is hardware; the software cannot override it. |
| d. Mitigates damage if a hazardous condition/event occurs | No | No mitigation in HA-R-01 is software. |
| e. Detects, reports, and takes corrective action if the system reaches a potentially hazardous state | No | The stop on loss of contact ([SRS-001](srs.md)) is a convenience for the operators, not a credited hazard control. |

## Determination

The rover drive software is not safety-critical: it meets none of the criteria, since every hazard of HA-R-01 is controlled by hardware it cannot override. So the [hazards](hazards.md) page lists no hazard that software is part of. The determination is made again if HA-R-01 credits a software control.

## Concurrence

Determined by the software lead with the facility's safety officer; software assurance concurred on 2027-01-12.
