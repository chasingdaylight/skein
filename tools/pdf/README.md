# tools/pdf

The text of a PDF, without anything to install: its objects and object streams, Flate, fonts' ToUnicode maps and widths, and the text operators of its pages, with the running headers and footers of a tagged PDF left out.

```sh
zig build pdftext -- FILE.pdf OUT.txt [RUNS.tsv]
```

`RUNS.tsv` gives each piece of text with its page and position (page, x, y, text), to read a table by its columns. It was written to take the text of NASA-STD-8739.8B and NASA-STD-7009B, which NASA publishes as PDF, into Skein's templates once; their text is kept by hand from there. It is not part of the Skein program, and may move into a library of file formats.

Not handled: encrypted files, filters other than Flate, and text drawn as images.
