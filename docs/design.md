# skein: design

Status: draft for acceptance by emanspeaks. Merging the pull request that adds this document accepts it; later changes go through pull requests that change it.

## 1. Purpose

skein manages the items that describe a project (needs, requirements, decisions, specification rules, design elements, tests) as plain text in git, with stable IDs and typed links, and turns them into checked, traceable, readable documents.

It exists because the free options each give up something essential:

- **Doorstop** keeps items as files in git but stores one item per file, which fragments prose, and is a Python tool with a thin view of the graph.
- **sphinx-needs** has the richest model (typed items, filters, matrices) but ties a project to Python, Sphinx and directive-heavy sources.
- **StrictDoc and OpenFastTrace** are requirements-shaped: good for "the system shall" lists, awkward for a specification written as connected prose.
- **Hosted tools** (OpenProject, GitLab requirements, DOORS) are interactive but keep the truth in a database, not in the repository.

skein takes the parts that work: Doorstop's files in git and its suspect links; sphinx-needs's typed items, filters and matrices; the Ferrocene Language Specification's atomic paragraphs with IDs and checksums; the Rust Reference's test annotations; StrictDoc's source-code markers and editing interface; OpenFastTrace's coverage across many levels.

### First users

- **Cesium** (cesiumlang): a language specification in the FLS style (prose made of atomic, categorized, numbered paragraphs), design proposals accepted by merge, conformance tests that cite rules, several implementations whose results are tracked per rule.
- **srapnol** (emanspeaks/srapnol): a NASA NPR 7150.2D documentation set kept today as Doorstop trees (system requirements, software requirements, design, test procedures) and narrative documents. Migrating it proves that skein is general.
- Other projects of emanspeaks's, hosted on GitHub, GitLab or Forgejo.

### Non-goals

- **Not a forge.** Discussion, code review and merging stay in the forge's issues and pull or merge requests. skein does plan the work (section 10), keeping the plan in git the way it keeps everything else.
- **Not a static site generator.** skein generates pages for an existing renderer (section 8).
- **Not a database.** Any index or cache skein builds is derived from the files and can be deleted.

## 2. Principles

1. **Plain text in git is the only source of truth.** Every item, link, review, baseline, schedule, date, estimate and assignment is in files under version control; there is no database. Everything else is generated. So all of it can be edited offline, with any editor or tool, and reviewed and merged like code.
2. **Forge-neutral.** skein works with nothing but a git repository. Integrations with GitHub, GitLab and Forgejo are adapters; the core never relies on a feature one of the three lacks (section 7).
3. **Schema-driven.** A project declares its item types, their attributes, the links allowed between them and the rules they must satisfy. skein has no built-in notion of "requirement" or "test".
4. **Prose-friendly.** An item can be a file of its own or a paragraph inside a document, so a specification reads as a document while every paragraph stays an item.
5. **Cheap for people and agents.** Small text files, readable IDs, one obvious place for everything; no generated file is ever edited by hand.
6. **Deterministic.** The same inputs give byte-identical outputs, so generated files diff cleanly and CI can check them.
7. **One small binary.** Zig, built with a pinned official release, no runtime dependencies, on Windows, Linux and macOS.

## 3. Concepts

- **Project:** a git repository with a `.skein/` directory at its root. A project can span several repositories, one of which holds what they share (section 10.5).
- **Schema:** the project's item types, attributes, link types and rules.
- **Item type:** a kind of item, for example `need`, `srs`, `design`, `test` for srapnol, or `proposal`, `rule`, `test` for Cesium. A type declares its ID pattern, its attributes, which links it may or must have, and its categories if any (for Cesium's rules: syntax, legality, dynamic semantics, implementation-defined, undefined, informative).
- **Item:** one identified piece of text with a type, attributes and links. Its **fingerprint** is a hash of its normative content (text and attributes the schema marks as normative), used to detect change.
- **Link:** a typed, directed reference from one item to another (`derives-from`, `implements`, `verifies`, `introduced-by`, ...). Each link records the fingerprint of its target when it was last reviewed; when the target changes, the link becomes **suspect** until someone reviews it again.
- **Document:** an ordered, readable assembly of items and narrative text (a specification chapter, an SRS, a design description). Narrative text is not an item and carries no obligations.
- **Citation:** a reference to an item from outside the item files: a test that says which rules it checks, a source file that says which requirement it implements, a commit or pull request that names an item.
- **Result:** the outcome of a test for an implementation, imported from a test run, attached to the items the test cites.
- **Baseline:** a named, immutable state of the item graph, normally a git tag, against which changes and coverage are compared.

## 4. Sources

### 4.1 Configuration and schema

A `.skein/` directory at the repository root holds skein's own files (emanspeaks, 2026-11-21): the configuration (item directories and documents, the schema, citation patterns, outputs, the forge and the other repositories of the project), and the data that belongs to no item file and that the forge does not hold, such as reviews of links, resources and calendars, time logs, and the last synced state of forge issues. Items and documents themselves live wherever the project wants them (`docs/`, `spec/`, beside the code); `.skein/` is for skein's bookkeeping. The format of its files is an open question (section 13), with ZON as the recommendation: native to Zig, no extra parser, and small.

### 4.2 Item files

An item of its own is a Markdown file with a front-matter block (ID, type, attributes, links with their reviewed fingerprints) and a body. This is close to Doorstop's Markdown items, so srapnol's trees can be converted mechanically (section 11).

### 4.3 Paragraph items in documents

In a document, any paragraph or list item can be an item by carrying a marker with its ID and, where the type has categories, its category. Links and attributes go in a compact form after the marker or in a short block below the paragraph. The marker syntax is an open question (section 13); it must be plain text that survives any Markdown renderer, cheap to type, and easy to find with grep. IDs are readable and hierarchical (`lex.comment.line`, `expr.as.narrow`), as in the Rust Reference, never random.

### 4.4 Citations in code and tests

Comments in source and test files cite items, with a configurable pattern per file type (for example `// spec: expr.as.narrow` in a Cesium test, `/// Implements SRS-012.` in a Zig doc comment). A directory can carry a file that cites items for every test inside it. skein checks that every citation names an existing item of an allowed type.

### 4.5 Results

skein imports test results in common formats (JUnit XML, TAP, and a small native JSON format for test drivers that write their own), records which implementation and version produced them, and attaches them to the items the tests cite.

## 5. The engine

A command-line tool, `skein`, with subcommands that each do one thing and fail with clear messages and a nonzero exit status:

| Command | Does |
| --- | --- |
| `check` | Validates the configuration, the schema, every item and link, every citation; reports duplicate, unknown and malformed IDs, missing required links, suspect links. The command CI runs. |
| `trace <id>` | Shows an item with everything above and below it, as text or JSON. |
| `coverage` | Reports, per item type and per category, which items lack the links or citations the schema expects (for example rules without tests), and the results per implementation. |
| `review <id>` / `clear <id>` | Records that an item, or the links to a changed parent, have been reviewed, by updating the stored fingerprints. |
| `new` / `move` / `link` | Creates items with the next free ID, renames IDs (keeping an alias), adds links; keeps files consistent so no one edits fingerprints by hand. |
| `import` | Converts Doorstop trees, and imports test results. |
| `export` | Writes the whole graph as JSON (for other tools and agents); later ReqIF for interchange with DOORS and similar. |
| `render` | Generates the pages a renderer turns into a site (section 8). |
| `lsp` | The language server (section 9). Later. |

The graph is built from the files on every run; for large projects a cache under the build directory may speed it up, but deleting it changes nothing.

## 6. Change, review and baselines

- Every item has a fingerprint over its normative content. A link stores the fingerprint of its target as last reviewed; a changed target makes the link suspect, and `check` reports it until `clear` records the review.
- Baselines are git tags; `check` and `coverage` can compare against one ("what changed since v0.3", "which rules are new and untested").
- Who approved a change is the forge's merge record (section 7); skein does not keep its own approval database.

## 7. Forges

The core needs only git. Everything that involves a forge goes through an adapter with one small interface, implemented for GitHub first, then GitLab and Forgejo:

- Resolve an item's links to issues and pull or merge requests (references written in item attributes or commit messages).
- Read who approved and merged a change, for reports that need it.
- Report `check` and `coverage` results in CI in the forge's format (annotations, summaries).

A capability that only one forge has (for example GitHub Projects fields or issue types) may be used by that adapter for convenience, but skein's own features never depend on it. Acceptance of a proposal or a design change is a merge, which all three forges have.

## 8. Rendering

skein does not render HTML itself. `render` writes Markdown pages (documents with every item anchored by its ID, generated matrices, coverage pages, per-item backlinks, filtered lists) in the dialect of the chosen renderer, and the renderer builds the site. The renderer is a replaceable last stage:

- **First: Zine**, run as its pinned standalone binary (so its Zig version does not bind skein's), with skein writing SuperMD (items as blocks with ID, category and data attributes). Zine fails the build on unknown pages and references, which doubles as a link check.
- If Zine's direction or pace stops fitting (it is in beta, has one maintainer, and takes no plugins), skein forks it under emanspeaks's account rather than working around it; emanspeaks agreed to this on 2026-11-21. Since skein only writes pages for it, a fork changes nothing in skein's sources.
- Others can be added (plain CommonMark for any generator; Quartz; a generator written in Cesium for cesiumlang.org later).
- Search and backlinks, which Zine lacks, are generated by skein as pages or data where they are needed.
- **Charts and diagrams that skein computes** (trace graphs, Gantt charts, burndown and burnup, resource load) are drawn by skein itself as static SVG, so they are deterministic, diff cleanly, and need no JavaScript or outside tool.
- **Mermaid** blocks written by hand in documents (flowcharts, sequence and state diagrams) are kept as they are and drawn in the reader's browser by a pinned copy of mermaid.js that the site ships. Mermaid's own command-line renderer is not used, since it needs Node.js and a headless browser. skein can also export its own graphs as Mermaid source, for pasting into issues and pull requests, which all three forges render.

## 9. Interactivity

1. **A language server** (`skein lsp`) for the item and document sources in any editor: go to definition on an ID, find references, completion of IDs and link targets, hover previews, diagnostics from `check`, rename of an ID across files.
2. **A VS Code view** on top of it: the item tree, trace views, coverage.
3. **Later, a local web interface** that edits the same files (like StrictDoc's or Doorstop's), for people who prefer forms to text. It writes files and commits; it never holds state of its own. Its planning views (section 10) are interactive: dragging a bar in the Gantt chart or a card on a board writes the change to the item's file.

## 10. Planning

skein plans and tracks the work as well as describing the product, taking from OpenProject the parts that matter: work packages with dates and dependencies, Gantt charts, boards, burndown, resource management, and comparing a plan with a baseline. The difference from OpenProject is the same as everywhere else in skein: the plan is files in git, not a database.

### 10.1 Work items

- Work is items of types the schema declares (for example `epic`, `task`, `milestone`), with planning attributes: status, start and finish dates or a duration, estimated and remaining effort, assignees, priority, and the version or milestone they belong to.
- Work items link to each other (parent and child; `precedes`/`follows` with a lag; `blocks`) and to the product items they serve (`implements` a requirement, `verifies` a rule), so a Gantt bar can be traced to the requirements behind it, and a requirement's coverage can show the work still open on it.
- **Scheduling:** an item is scheduled automatically from its predecessors and its duration, or by hand with fixed dates, as OpenProject's two modes are. skein computes the schedule, the critical path and the slack, and `check` reports what cannot be met: a date before a predecessor's finish, a child outside its parent, a milestone the plan misses.
- **Time spent:** effort logged against an item (who, when, how long) is kept in files beside it, for actual-versus-estimate reports.

### 10.2 Resources

- A resources file lists the people (and, where wanted, roles or teams), each with a capacity (hours per week, or a share of full time) and a calendar of working days, holidays and absences. It lives in `.skein/`, in the planning repository when the project has several (section 10.5).
- From assignments and effort skein computes each person's load per week, shows it next to their capacity, and reports overallocation in `check` and as a chart.
- People are identified by a handle the project chooses (for example their forge user name), mapped per forge by the adapter, so a plan moves between forges unchanged.

### 10.3 Views

- **Gantt chart:** bars, milestones, dependencies and the critical path, by version, by person, or for any filter; with a baseline's bars beside the current ones to show slippage.
- **Burndown and burnup** per version or milestone, in items or effort. Their history comes from git: the state of the plan at each commit (or each day's last commit) gives the series, so nothing records snapshots by hand and the chart can be rebuilt for any past date.
- **Boards** by status, assignee or version, and a **roadmap** of versions with what each contains and how far along it is.
- **Resource load** per person and week, as a table and a chart.
- The same filters as everywhere else ("open tasks implementing chapter 4", "work on rules with no test"), as pages and in `skein export`.

### 10.4 Forge issues

Discussion stays in the forge, so a work item can be linked to an issue, and an issue can be a work item of its own without a separate file. Either way, git holds the plan:

- What the forge does not hold (dates, durations, estimates, dependencies with lags, effort, capacity) is only in git: in the item's file, or in `.skein/` for an issue that has no file.
- What the forge does hold (title, open or closed, assignees, labels, milestone) is read through the adapter, and `skein sync` writes it into `.skein/` as a commit. So the whole plan, its history included, is in git: the charts, `check` and offline work need no forge, and moving to another forge loses nothing.
- `skein sync` can also write the other way, creating or updating issues from items. The configuration says, field by field, which side wins when both changed.

Projects that do not want issues use items alone.

### 10.5 Projects of several repositories

A project spread over several repositories (a compiler, a website, an editor extension, like Cesium's) can have one **planning repository** that holds what they share: the resources and calendars, work that spans repositories (milestones, roadmaps, epics), and the cross-repository views. Cesium's workspace repository is a natural one.

- Each repository's `.skein/` names the planning repository, and the planning repository's names the others, by a short project name and a location: a path to a local checkout (a sibling or a submodule) or a remote URL that skein clones. skein reads them as git repositories, never through a forge's API, so this works offline and on any forge, and can mix forges.
- Items and issues in other repositories are cited by a qualified reference (`cesium:expr.as.narrow`, `vscode-cesium#24`), checked by `check` like local ones; the forge adapter turns issue references into links.
- A repository can also be used alone: without the planning repository at hand, `check` reports cross-repository references as unresolved instead of failing on them, unless the configuration requires them.

## 11. Migration

- **Doorstop:** `skein import doorstop` converts a Doorstop tree (items, links, reviewed fingerprints, `references`) into skein items and a schema, so srapnol can switch without losing history or reviews.
- **Cesium:** the specification draft and the S0 grammar on cesiumlang.org, the reference pages, and the bootstrap and differential test corpora move into skein's format; the decision records become proposals for emanspeaks's review.

## 12. Phases

1. **This design**, accepted by merge.
2. **Core and CLI:** configuration and schema, item files and paragraph items, citations, `check`, `trace`, `coverage`, `review`/`clear`, `export` (JSON). Proven on Cesium's S0 chapter and its bootstrap tests, and on an import of srapnol's Doorstop trees. From here, skein's own requirements are written in skein.
3. **Rendering and results:** `render` for Zine, result import, baselines, the forge adapter for GitHub with CI output.
4. **Planning:** work items, scheduling and the critical path, resources and load, Gantt, burndown and burnup, boards and the roadmap as rendered pages; `skein sync` with GitHub issues. Proven on skein's own work and on Cesium's roadmap.
5. **Editing:** `new`/`move`/`link`, the language server, the VS Code view.
6. **Wider:** GitLab and Forgejo adapters, ReqIF export, the web interface with interactive planning views.

## 13. Open questions for emanspeaks

1. **Configuration format:** ZON (recommended: native to Zig, small), TOML, or YAML (closest to Doorstop).
2. **Paragraph marker syntax** in documents, for example a trailing `{#lex.comment.line .legality}` attribute (Pandoc and Markdown-attribute style), a leading `r[lex.comment.line]` line (Rust Reference style), or an HTML comment. Recommendation: the trailing attribute form; it reads well, many tools already know it, and it carries a category without a second marker.
3. **ID scheme per project:** readable hierarchical IDs (recommended for specifications) and numbered IDs (`SRS-012`, as srapnol uses) both supported, chosen per item type in the schema.
4. **Zig version:** the latest official release at the time of each skein release (0.17.1 today), pinned per release.
5. **Names inside `.skein/`** (for example `config.zon`, `resources.zon`, `sync/`), settled with the first code.
6. **Planning's place in the phases:** after rendering (recommended, since its views are rendered pages), or earlier, if Cesium's roadmap should move from the GitHub Project to skein soon.

## 14. Requirements of skein itself

Until phase 2 works, this document is skein's requirements. Then they move into skein's own format in this repository, traced to its tests, and this document becomes a design description that cites them.
