# Notes for coding agents

What a coding agent working on Skein needs to know besides the code, the [readme](readme.md), the [design](docs/design.md) and the [issues](https://github.com/chasingdaylight/skein/issues). Notes about one machine (paths, hosts, caches) go in `CLAUDE.local.md`, which is not committed. Mistakes made more than once are written down here so they are not made again.

The repository's setup follows zfls (cesiumlang/zfls) and rstd (randyos-org/rstd), the newer Zig projects of emanspeaks's: when something here is missing, do it as they do.

## What Skein is

Plain-text requirements, specifications and traceability kept in git. `docs/design.md` is the design: where Skein is going and why; read it before changing anything substantial. A change to the design starts as a pull request that changes it: merging it is accepting it.

## Requirements and tests

- `docs/requirements/` holds Skein's requirements, in Skein's own format (`.skein/` at the root is Skein's own project). What Skein does is what they say.
- A change to what Skein does changes its requirement in the same pull request: a new `%req[...]` paragraph, or a changed one. A requirement that goes away keeps its marker, with `status=removed`; an ID is never changed or used again.
- A test file says which requirements it checks, in a `// req:` comment before its imports (or before its tests, in a source file that has them at its end). Every implemented requirement has a test that cites it; `skein coverage --profile implemented` lists the ones that have none.
- What the design promises and the code does not do yet is in `docs/requirements/planned.md`, `status=planned`. Building it turns each into requirements of its own, with tests.

## Rules

- Git and the files are the only source of truth. Forges (GitHub, GitLab, Forgejo) are reached only through adapters, and nothing in the core may rely on a feature one of them lacks.
- One codebase: no dependency is fetched at build or run time, or run as a separate tool. Code taken from another project (Zine and what it builds on, mermaid.js) is copied in as a fork Skein maintains: read before it goes in, recorded with its origin (project, commit) and license, updated only by a reviewed change, and only after asking emanspeaks.
- Zig over other languages: the tool, build steps, generators, test drivers and tools are Zig, built with the pinned official release (0.17.1). No Python, Node or Java in the repository; its scripts are bash or batch. Scratch scripts an agent writes to analyze something (a document's layout, a table) may be in any language, Python too, and stay in its scratchpad, never committed (emanspeaks, 2026-11-22).
- Never run a command that downloads or installs software without asking first, package managers included (markdownlint through `npx` excepted).
- The repository owner is `emanspeaks` in every file, issue and pull request; write `@emanspeaks` only to ask for his input, since every `@` notifies him.

## The backlog: GitHub issues

- Open work is the [issues](https://github.com/chasingdaylight/skein/issues), and their order is the project [Skein Roadmap](https://github.com/orgs/chasingdaylight/projects/1): its rows are in priority order, the next thing to work is the first that is not done, and a new issue goes in at its place with the milestone of the next version. Each issue is one task, landed in one pull request; split a larger plan into one issue per step.
- Whose action is next is said three ways, kept the same (emanspeaks, 2026-11-21): emanspeaks is the assignee only where he must answer or do something an agent cannot; everything else is the agent's, with no assignee, the label `agent`, and "Next action: agent" in the project. When the next step changes hands, change all three; `bash /c/cesium/workspace/.claude/skills/roadmap-project/scripts/next-action.sh chasingdaylight chasingdaylight` sets the field and the labels from the assignees for the whole project.
- Milestones are release versions (`v0.2.0`), and every open issue is in the next one (emanspeaks, 2026-11-26); the project, not the `dev` to `main` pull request, tracks the issues, so its description lists none.
- Labels: `blocked` with a `**Blocked:**` line naming the outside cause, `awaiting input` for a decision emanspeaks makes, `housekeeping` for readability and structure work. `**Needs:**` links the issues that must land first.
- Pull requests take the release-note labels of `.github/release.yml` (`fix`, `feature`, `performance`, `tests`, `refactor`, `ci`, `skip-changelog`); their titles are the release notes.
- GitHub is the record of the work, not the chat: a bug, follow-up or decision for emanspeaks gets an issue when it is found.

## Git

- `main` and `dev`. Work goes on a branch from `dev` and reaches `dev` through a pull request; `main` only takes releases, through the `dev` to `main` pull request, which emanspeaks merges.
- A release is made by CI when `main` gets a version (`build.zig.zon`) that has no tag and something a release ships has changed since the last tag (not documentation, the site or CI alone: `docs-only.txt` and `ci-only.txt` in `.github/workflows/`; a pull request into `main` that only changes documentation is linted and tested on one platform): it tags the commit, publishes Skein for each platform and the VS Code extension (`editors/vscode/`, one package per platform with that platform's Skein in `bin/`, and a universal one; published by `marketplace.yml` and `open-vsx.yml`), closes the version's milestone (emanspeaks, 2026-11-27), and begins the next patch version on `dev`. Listing a release of the action (`action.yml`) in the GitHub Marketplace is the one step CI cannot take, as GitHub has no API for it: emanspeaks edits each release on GitHub after CI publishes it, ticks **Publish this Action to the GitHub Marketplace**, and updates it (the release job's summary links the page); until then the Marketplace shows the release before (emanspeaks, 2026-11-27). Every place that states the version (`build.zig.zon`, the extension's `package.json`, `package-lock.json` and changelog) is the same; `.github/workflows/version.sh` lists and checks them (CI and `land.sh` run it) and sets them all (`version.sh set NEXT`). A new place that states the version goes into it. Never tag or publish by hand.
- On GitHub, agents act as the GitHub App Chasing Daylight Agent, never as emanspeaks: `GH_TOKEN="$(bash /c/scratch/github-apps/app-token.sh chasingdaylight)"` for `gh`, and `bash /c/scratch/github-apps/app-git.sh chasingdaylight <git arguments>` for commits, fetches and pushes, with the harness's AI attribution trailer. Never print, copy or commit anything in `/c/scratch/github-apps/chasingdaylight/`. What an app cannot do stays with emanspeaks: merging `dev` into `main`, the extension registries, and his own repositories (the documentation mirror `emanspeaks/skein-docs`).
- Commit messages are one short line (about 50 characters), with no body; rationale and test results go in the pull request or the issue.
- Before a commit, check `git diff --cached` and `git status` so a commit takes only your own changes. emanspeaks's uncommitted edits to `CLAUDE.md`, the LTeX files and the readme go into the next commit.
- After a merge, delete the branch, locally and on GitHub.
- `.local-gitignore` is this checkout's own ignore file (`git config core.excludesFile .local-gitignore`).

## Zig 0.17: what not to use

Skein builds with Zig 0.17.1, whose standard library marks many older declarations deprecated in their doc comments. The compiler does not warn about them, so they creep back in. Use the replacement:

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
- Data taken from an outside source says where it came from and when. A standard's text in a template is taken once and kept by hand from then on, when the standard is revised (emanspeaks, 2026-11-22); what a generator kept in the repository writes is fixed in the generator.
- Markdown: one line per paragraph or list item, no hard wraps; no markdownlint warnings: `npx markdownlint-cli2 "**/*.md"` before finishing a change to a `.md` file. Don't add dictionary words on your own; list new ones in your report.

## Commands

- Never write a redirect that can create a `nul` file: `/dev/null` in Bash, `$null` in PowerShell.
- Search with `rg` (with an explicit path) or the Grep tool, excluding `zig-pkg`, `.zig-cache` and `zig-out`.
- Kill only processes you started, matched by their own command line.

## Checks before a pull request

`zig build test`, `zig fmt --check build build.zig src templates tools`, `npx markdownlint-cli2 "**/*.md"`, cspell (`npx cspell --no-progress "**/*.md" "src/**" "templates/**" "tools/**"`), and Skein on itself: `zig build`, then `zig-out/bin/skein check` and `zig-out/bin/skein coverage --profile implemented`. For a change to the VS Code extension (`editors/vscode/`, TypeScript bundled by esbuild), in that directory: `npm ci`, `npm audit`, `npm run typecheck`, `npm run unit` and `npm run build`; its unit tests cite requirements as Skein's do (`// req:`). CI does not run on pull requests into `dev` (only on those into `main`, and when started by hand: `gh workflow run ci.yml --ref BRANCH`), so these checks are what stands between a change and `dev`; say in the pull request which were run. `tools/agent/land.sh` runs them and lands the change (the `land-a-change` skill).

## Skills, scripts and tools

- `.claude/skills/`: `land-a-change` (checks, pull request, merge, CI), `roadmap-issue` (filing at a place in the Roadmap, Rank, whose action is next, the board), `skein-template` (adding or changing a template), `standard-text` (taking a standard's text into a template).
- `tools/agent/`: the scripts those skills run: `land.sh`, `file-issue.sh`, `rank.sh`, `board.sh`, and `register-templates.sh`, which writes the file list of `templates/__root__.zig` (run it after adding or removing a template's file).
- `tools/` otherwise holds programs that are not part of the Skein program, built by `zig build` steps of their own, tested by `zig build test`, and listed in `.github/workflows/ci-only.txt`: `tools/pdf` (`zig build pdftext`, the text of a PDF with positions) and `tools/npr7150` (NPR 7150.2D's NODIS pages as Skein documents). They are kept for reuse, and may move into a library of file formats such as rstd.

## Traps met before

- In the Bash tool on this machine, a command line containing a single quote fails ("unexpected EOF while looking for matching") before it runs: put such a command in a script file and run the file.
- Zig result locations: `v = .{ .stream = .{ .dict = v.dict } }` overwrites `v` while reading it; build the new value in a `const` first.
- Windows Python does not see MSYS paths such as `/tmp`; give scratch scripts Windows paths.
