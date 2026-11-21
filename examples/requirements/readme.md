# Example: requirements, each a file of its own

System requirements, the software requirements that refine them, a test procedure that verifies those, and code that says what it implements: a small V-model, as standards such as NASA's NPR 7150.2 ask for.

Try, from this directory:

```text
skein check
skein trace SYS-001
skein coverage
skein export items
```

Then change a requirement and see what follows from it:

1. Edit the text of `docs/system/SYS-001.md`.
2. `skein check` now reports two things: the links from `SRS-001` and `SRS-002` are suspect, since what they refine has changed; and `SYS-001` has the status `approved` without an approval of what it now says.
3. `skein impact` lists everything that rests on the requirement, down to the test procedure and the code.
4. `skein clear SYS-001` records that the software requirements were looked at again, and `skein approve SYS-001` approves the new text.

| File | What it shows |
| --- | --- |
| `.skein/types/` | Numbered IDs, a status that needs an approval, verification methods, attributes. |
| `.skein/links/` | Link types that are required, reviewed and expected. |
| `.skein/reviews/`, `.skein/approvals/` | The records skein keeps: written by `skein review` and `skein approve`, never by hand. |
| `docs/` | Item files: TOML front matter, then the text. |
| `src/record.c` | Citations in code. |

`SRS-003` is verified by inspection and has no test procedure, so `skein coverage` lists it as not verified by one; records of other kinds of verification are to come.
