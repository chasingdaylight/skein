+++
document = "SW-RISK"
revision = "Draft"
item = "PRD-21"
maturity = "U"
+++

# Software risks

The software risks, identified and managed continuously (%[SWE-086]) under the project's risk management (NPR 8000.4), with the security risks of %[SWE-154] and %[SWE-156].

| Risk | Likelihood | Consequence | Mitigation | Status |
| --- | --- | --- | --- | --- |
| The controller arrives late, leaving no time to test on it before the field test. | Medium | Medium | The unit tests run on the host; the stand procedures are kept short. | Open |
| Radio interference in the test field makes the rover stop often (SRS-001). | Low | Low | The timeout is set from the ground station's rate, and can be changed by a release. | Open |
