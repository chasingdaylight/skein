+++
document = "SW-STPR"
revision = "Draft"
item = "PRD-07"
maturity = "D"
+++

# Software test procedures

The test procedures and cases (%[SWE-065]), after handbook topic 5.14. Each is an item of the type `procedure`, `TST-001` and on, linked by `verifies` to the requirements it verifies; its results are recorded with `skein result` or a results file, and summarized in the [test report](test-report.md).

The unit tests in `tests/` cite the requirements they verify (`// verifies: SRS-001`); these procedures are carried out on the rover.

## Environment and schedule

The rover on its stand, wheels off the ground, with the ground station's radio; after each release.

## Test cases

%procedure[TST-003 unit verifies=SRS-001 verifies=SRS-002 verifies=SRS-003] Build and run the unit tests of `tests/` on the host: it passes when every test passes.

%procedure[TST-001 system verifies=SRS-001] Drive the wheels at 0.3 m/s, switch off the ground station's radio, and time the wheels to a stop: it passes when they stop within 2 seconds.

%procedure[TST-002 system verifies=SRS-004] After a run of TST-001, read the log from the SD card: it passes when every command sent is there, with its time, in order.
