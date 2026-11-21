# Notes for coding agents

What a coding agent working on skein needs to know besides the code, the [readme](readme.md), the [design](docs/design.md) and the [issues](https://github.com/emanspeaks/skein/issues). Notes about one machine (paths, hosts, caches) go in `CLAUDE.local.md`, which is not committed. Mistakes made more than once are written down here so they are not made again.

The repository's setup follows zfls (cesiumlang/zfls) and rstd (randyos-org/rstd), the newer Zig projects of emanspeaks's: when something here is missing, do it as they do.

## What skein is

Plain-text requirements, specifications and traceability kept in git. `docs/design.md` is the design; read it before changing anything substantial. Until skein can describe itself in its own format, that document is the source of its requirements, and a change to the design starts as a pull request that changes it: merging it is accepting it.

## Rules

- Git and the files are the only source of truth. Forges (GitHub, GitLab, Forgejo) are reached only through adapters, and nothing in the core may rely on a feature one of them lacks.
- One codebase: no dependency is fetched at build time or run as a separate tool; code taken from another project is merged in with its license and origin recorded, after asking emanspeaks.
- Zig over other languages: the tool, build steps, generators, test drivers and tools are Zig, built with the pinned official release (0.17.1). No Python, Node or Java; scripts are bash or batch.
- Never run a command that downloads or installs software without asking first, package managers included (markdownlint through `npx` excepted).
- The repository owner is `emanspeaks` in every file, issue and pull request; write `@emanspeaks` only to ask for his input, since every `@` notifies him.

## The backlog: GitHub issues

- Open work is the [issues](https://github.com/emanspeaks/skein/issues). Each issue is one task, landed in one pull request; split a larger plan into one issue per step.
- The current milestone is the task list in the description of the open `dev` to `main` pull request, in work order; check an issue off there when it lands on `dev`.
- Labels: `backlog` for what is outside the milestone, `blocked` with a `**Blocked:**` line naming the outside cause, `awaiting input` for a decision emanspeaks makes, `housekeeping` for readability and structure work. `**Needs:**` links the issues that must land first.
- Pull requests take the release-note labels of `.github/release.yml` (`fix`, `feature`, `performance`, `tests`, `refactor`, `ci`, `skip-changelog`); their titles are the release notes.
- GitHub is the record of the work, not the chat: a bug, follow-up or decision for emanspeaks gets an issue when it is found.

## Git

- `main` and `dev`. Work goes on a branch from `dev` and reaches `dev` through a pull request; `main` only takes releases, through the `dev` to `main` pull request, which emanspeaks merges.
- For now agents commit, push and open pull requests with emanspeaks's own git identity and `gh`, with the harness's AI attribution trailer; no GitHub App is installed here yet.
- Commit messages are one short line (about 50 characters), with no body; rationale and test results go in the pull request or the issue.
- Before a commit, check `git diff --cached` and `git status` so a commit takes only your own changes. emanspeaks's uncommitted edits to `CLAUDE.md`, the LTeX files and the readme go into the next commit.
- After a merge, delete the branch, locally and on GitHub.
- `.local-gitignore` is this checkout's own ignore file (`git config core.excludesFile .local-gitignore`).

## Zig 0.17: what not to use

skein builds with Zig 0.17.1, whose standard library marks many older declarations deprecated in their doc comments. The compiler does not warn about them, so they creep back in. Use the replacement:

| Deprecated | Use |
| --- | --- |
| `std.fmt.allocPrint(a, fmt, args)` | `a.print(fmt, args)` |
| `std.fmt.bufPrint(buf, fmt, args)` | `std.mem.print(buf, fmt, args)` |
| `std.mem.indexOf`, `indexOfScalar`, `indexOfAny` and the rest | `std.mem.find`, `findScalar`, `findAny` and the rest |
| `std.mem.lastIndexOf`, `lastIndexOfScalar` | `std.mem.findLast`, `findScalarLast` |
| `std.fs.path` | `std.Io.Dir.path` |
| `std.StringArrayHashMapUnmanaged` | `std.array_hash_map.String` |
| a hash map or `EnumMap` initialized with `.{}` | `.empty` |
| `std.ArrayList(T).getLast()` | `items[items.len - 1]` |
| `std.builtin` | `std.lang` |
| `builtin.mode` | `builtin.optimize` |
| `-Doptimize=Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall` | `-Doptimize=debug`, `safe`, `fast`, `small` |
| `Build.Step.Run.addArtifactArg(x)` and the other `add...Arg(x)` | the `...Arg2(x, .{})` ones |

The list is not complete (zfls's `CLAUDE.md` has a longer one); the standard library is the reference: a deprecated declaration has a doc comment starting with "Deprecated", which ZLS shows on hover.

## Style

- `.editorconfig` is authoritative. Zig: four spaces, as `zig fmt` writes them; everything else two.
- `const sysinfo = @import("builtin");`, never `builtin`. Every `@import` is a `const` near the top of the file. A switch mapping tags to values has one prong per distinct value.
- Files ideally under 500 lines, never over 1000, one per logical unit; a folder for a unit too complex for one file. Test-only code goes in `_test/` folders. Code several files use goes in one shared file, never copied.
- Panics only for unrecoverable states; bad input is an error. Exact error sets with plain names; slices, not pointers plus lengths; allocator first; `try`, never `catch @panic("OOM")`.
- Comments sparse and terse, no em dashes (semicolons instead), American English. Don't remove comments or commented-out lines you didn't write.
- Data derived from an outside source says where it came from and that it is regenerated, not edited; generated files are fixed in their generator.
- Markdown: one line per paragraph or list item, no hard wraps; no markdownlint warnings: `npx markdownlint-cli2 "**/*.md"` before finishing a change to a `.md` file. Don't add dictionary words on your own; list new ones in your report.

## Commands

- Never write a redirect that can create a `nul` file: `/dev/null` in Bash, `$null` in PowerShell.
- Search with `rg` (with an explicit path) or the Grep tool, excluding `zig-pkg`, `.zig-cache` and `zig-out`.
- Kill only processes you started, matched by their own command line.
