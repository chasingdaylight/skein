+++
document = "SRS"
revision = "Draft"
+++

# Software requirements specification

What the software shall do and be (ISO/IEC/IEEE 29148:2018, clause 9.6, in skein's words). Its requirements are items of the type `software`, `SRS-001` and on, each linked by `allocates` to the system requirement it comes from, with its category and verification method.

## Introduction

Purpose and scope; the product's perspective (its interfaces to the system, users, hardware, other software and communications, its memory and operations, and adaptation to its sites); its functions; its users; its limitations; assumptions and dependencies; how requirements are apportioned among releases.

## Functions

%software[SRS-001 functional verification=test priority=high allocates=SYS-001] The software shall produce, for a product, the list of stakeholder requirements it meets. (An example: replace it.)

## Performance and usability

## Interfaces

## Data

The data the software keeps, and its rules.

## Design constraints and standards compliance

## Software system attributes

Reliability, availability, security, maintainability and portability.

## Verification

How each requirement is verified; the [verification](verification.md) page lists them.
