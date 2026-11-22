+++
document = "PM-LIFECYCLE"
revision = "Draft"
+++

# Life cycle and milestones

The project's life cycle (%[PM-2.2.1]): its phases, from Pre-Phase A to Phase F, and the key decision points that open them, each an item of the type `kdp` (`KDP-A` to `KDP-F`) with its date, the milestones of the project's schedule. The life-cycle reviews held before them (%[PM-2.2.4], %[PM-2.2.5]) are those of NPR 7123.1D; with the `npr7123.1d` template, they are items of the type `review` with their dates.

%kdp[KDP-B phase=B status=planned date=2027-03-01] The decision to enter Phase B, Preliminary Design and Technology Completion. (An example: replace it.)

```skein
list kdp columns=phase,date,status,authority
```
