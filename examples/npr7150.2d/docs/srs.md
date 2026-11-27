+++
document = "SW-SRS"
revision = "Draft"
item = "PRD-10"
maturity = "P"
+++

# Software requirements specification

The software requirements (%[SWE-050]), each specific, testable and traceable, with how it is verified (handbook topic 5.09). Each is an item of the type `requirement`, `SRS-001` and on, linked by `derives` to the higher-level requirement it comes from and by `addresses` to the hazards it is part of; its verification method is `verification=`.

## Introduction

The drive software runs on the rover's controller. It takes drive commands from the ground station over the radio link and sets the speed of the wheel motors.

## Functional requirements

%requirement[SRS-001 functional verification=test derives=SYS-001] The software shall command zero speed within 2 seconds of receiving the last valid drive command.

%requirement[SRS-002 functional verification=test derives=SYS-002] The software shall not command a speed above 0.5 meters per second.

## Performance and quality requirements

%requirement[SRS-004 quality verification=inspection derives=SYS-003] The software shall log each drive command it receives, with the time it was received.

## Interface requirements

%requirement[SRS-003 interface verification=test derives=SYS-001] The software shall accept drive commands of a speed and a heading, at up to 10 commands a second.

## Design and implementation constraints

The safety constraints and assumptions between hardware, operator and software (%[SWE-184]): the rover's hazards are controlled by hardware (the [safety-criticality determination](safety-criticality.md)), and the software assumes that the hardware emergency stop may cut motor power at any moment. The software is written in C, to the facility's coding standard.

## Qualification provisions

How each requirement is verified: test, analysis, inspection or demonstration, each with its criteria. The [traceability](traceability.md) page shows each requirement with what verifies it.

## Rationale, assumptions and limitations

The 2-second timeout of SRS-001 is five missed commands at the ground station's rate of 2.5 a second.
