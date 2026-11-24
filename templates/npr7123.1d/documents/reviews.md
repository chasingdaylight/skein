+++
document = "SE-REVIEWS"
revision = "Draft"
+++

# Life-cycle and technical reviews

The reviews the project holds (%[SE-33], %[SE-34]), each an item of the type `review` (`REV-001` and on), of its kind, with its date (a milestone of the project's schedule) and its board, linked by `judged-by` to the table of entrance and success criteria of Appendix G that applies (a project's PDR by Table G-6). Which reviews a project holds, and when, is set by its program or project management NPR (NPR 7120.5 for space flight).

%review[REV-001 kind=PDR status=planned judged-by=G-6 date=2027-06-15] The preliminary design review. (An example: replace it.)

```skein
list review columns=kind,date,status,judged-by
```

## Checklists

At each review, each criterion of its table is judged, an item of the type `review-check`, linked by `fulfills` to the criterion (`G-6.e1`), with the review it was judged at, met or not, the evidence, and the actions left open:

```text
%review-check[rev-001.e1 met fulfills=G-6.e1 review=REV-001 evidence="SRR closure memo"] The SRR's RFAs are closed.
```

```skein
list review-check columns=review,category,fulfills,evidence,actions
```
