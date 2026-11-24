---
name: standard-text
description: Take the text of a standard or procedural requirement (NASA NPRs from NODIS, NASA standards as PDF) into a skein template as read-only items, once - fetching, tools/pdf, reading tables by column, writing the Markdown, and recording where it came from. Use when a template needs a standard's requirements.
---

# A standard's text in a template

<!-- cspell:ignore gsfc swehb -->

The text is taken once and kept by hand from then on, when the issuer revises it (emanspeaks, 2026-11-22). The program that takes it need not be kept; the scripts that read one document's layout belong in the scratchpad, in any language (Python is fine there), never in the repository. What is kept is reusable code: `tools/pdf` (a PDF reader) and `tools/npr7150` (the NODIS HTML of NPR 7150.2D).

1. **The latest revision:** the trailing letter is the revision (NPR 7150.2D is revision D). Check NODIS (`nodis3.gsfc.nasa.gov`) for NPRs and `standards.nasa.gov` for standards; take the approved copy, not a draft (a draft says "official draft has not been approved").
2. **Fetch politely:** one request at a time with pauses; the Internet Archive (`https://web.archive.org/web/2026/URL`) when a site refuses automated requests, never the refusing site again. swehb.nasa.gov is read only through the archive.
3. **PDF:** `zig build pdftext -- FILE.pdf OUT.txt RUNS.tsv` gives the text, and with `RUNS.tsv` each piece with its page and position, to read a table by its columns (bin the runs by x, join the runs of a line, start a row where the ID column has one).
4. **Write the Markdown** under `templates/NAME/project/standards/NAME/`: a first-line comment naming the document, its revision and date, where it was taken from, the date, and that it is kept by hand; the requirements as items of a numbered type (`SWE-013`, `MS-40`), lettered sub-parts as parts (`.a`), notes and rationale quoted under them (`> Note:`), headings as the document has them. Escape `*`, `_`, backquotes, `<` and `%[`.
5. **Check it:** every requirement the document numbers is there once (compare with its matrix or index), `skein check` reads it with no problems in a project from the template, markdownlint passes.
