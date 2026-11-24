# tools/npr7150

Writes NASA's NPR 7150.2D, NASA Software Engineering Requirements, as Skein documents for the `npr7150.2d` template: each requirement (`SWE-nnn`) an item of the type `swe`, its lettered sub-parts its parts, its notes under it, with the classes and tailoring authority of Appendix C and a link to its page in the NASA Software Engineering Handbook (NASA-HDBK-2203), which interprets it. It took the template's text once, on 2026-11-22; that text is kept by hand from then on, when NASA revises the NPR (emanspeaks, 2026-11-22). The program is kept for reuse (reading NODIS pages, and the handbook's reading of each requirement from `guidance.csv`), not to be run again over the template.

```sh
bash tools/npr7150/fetch.sh /tmp/npr                  # chapters 2 to 5 and appendix C, from NODIS
zig build npr7150 -- /tmp/npr templates/npr7150.2d/project/standards/npr7150.2d 2026-11-22
```

## Sources

- **The NPR:** its pages on NODIS, `https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=Chapter2` (to `Chapter5`, and `AppendixC`); the effective date is read from the pages, the date they were fetched is given on the command line, and both are written at the head of each document. As a work of the United States government, its text may be included.
- **`handbook.csv`:** the title and page of each requirement in the handbook, from the handbook's requirement index (version D, `https://swehb.nasa.gov/spaces/SWEHBVD/pages/102695222/C.+Project+Software+Requirements`, read through the Internet Archive, capture of 2026-10-03), as noted on chasingdaylight/skein#133.
- **`guidance.csv`:** the handbook's reading of each requirement (its meaning, objective evidence, documents, milestones, small projects, software assurance), paraphrased from a review of every SWE page of the handbook through the Internet Archive (captures of 2026-03 to 2026-10), 2026-11-22.
