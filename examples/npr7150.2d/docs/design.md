+++
document = "SW-SDD"
revision = "Draft"
item = "PRD-14"
maturity = "D"
+++

# Software design description

The architecture (%[SWE-057]) and detailed design (%[SWE-058]) of the software, after handbook topic 5.13; the interfaces, as an interface design description (topic 5.02) here or of their own. Each component is an item of the type `design`, `DES-001` and on, linked by `satisfies` to the requirements it meets; the code that implements it cites it.

## Design and trade decisions

One loop at 20 Hz on the controller, with no operating system: it reads the radio, decides the speed, and sets the motors.

## Architecture

Three components, each a C file: the link monitor reads commands, the speed governor turns them into motor speeds, and the logger records them.

## Components

%design[DES-001 satisfies=SRS-001 satisfies=SRS-003] Link monitor (`src/link.c`): decodes each drive command from the radio, and reports the link lost when no valid command has come for 2 seconds.

%design[DES-002 satisfies=SRS-002] Speed governor (`src/speed.c`): limits the commanded speed to 0.5 m/s, and commands zero when the link monitor reports the link lost.

%design[DES-003 satisfies=SRS-004] Logger (`src/log.c`): writes each command, with the controller's clock, to the log on the SD card.

## Interfaces

The radio delivers a command as 6 bytes: speed in mm/s (2 bytes), heading in tenths of a degree (2 bytes), and a CRC-16.

## Resources and rationale

The loop takes under 5 ms of its 50 ms period on the controller.
