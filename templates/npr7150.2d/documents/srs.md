+++
document = "SW-SRS"
revision = "Draft"
+++

# Software requirements specification

The software requirements (%[SWE-050]), each specific, testable and traceable, with how it is verified (handbook topic 5.09). Each is an item of the type `requirement`, `SRS-001` and on, linked by `derives` to the higher-level requirement it comes from and by `addresses` to the hazards it is part of; its verification method is `verification=`.

## Introduction

Purpose and audience; scope; an overview of the software and its context.

## Functional requirements

States and modes, data, safety, control, algorithms, inputs and outputs, security and privacy, fault management.

%requirement[SRS-001 functional verification=test] The software shall start in a known safe state. (An example: replace it.)

## Performance and quality requirements

Timing, reliability, maintainability, availability, and the use of computer resources.

## Interface requirements

External and internal software, users, hardware, communications and services.

## Design and implementation constraints

%[SWE-184].

## Qualification provisions

How each requirement is verified: test, analysis, inspection or demonstration, each with its criteria. The [traceability](traceability.md) page shows each requirement with what verifies it.

## Rationale, assumptions and limitations
