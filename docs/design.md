# Skein: design

Status: draft for acceptance by emanspeaks. Merging the pull request that adds this document accepts it; later changes go through pull requests that change it.

## 1. Purpose

Skein manages the items that describe a project (needs, requirements, decisions, specification rules, design elements, tests) as plain text in git, with stable IDs and typed links, and turns them into checked, traceable, readable documents.

It exists because the free options each give up something essential:

- **Doorstop** keeps items as files in git but stores one item per file, which fragments prose, and is a Python tool with a thin view of the graph.
- **sphinx-needs** has the richest model (typed items, filters, matrices) but ties a project to Python, Sphinx and directive-heavy sources.
- **StrictDoc and OpenFastTrace** are requirements-shaped: good for "the system shall" lists, awkward for a specification written as connected prose.
- **Hosted tools** (OpenProject, GitLab requirements, DOORS) are interactive but keep the truth in a database, not in the repository.

Skein takes the parts that work: Doorstop's files in git and its suspect links; sphinx-needs's typed items, filters and matrices; the Ferrocene Language Specification's atomic paragraphs with IDs and checksums; the Rust Reference's test annotations; StrictDoc's source-code markers and editing interface; OpenFastTrace's coverage across many levels.

### Non-goals

- **Not a forge.** Discussion, code review and merging stay in the forge's issues and pull or merge requests. Skein does plan the work (section 10), keeping the plan in git the way it keeps everything else.
- **Not a general static site generator.** Skein renders its own documents and views (section 8); it is not a tool for building arbitrary websites.
- **Not a database.** Any index or cache Skein builds is derived from the files and can be deleted.
- **Not access control.** Who may read or change what is the repository's and the forge's business; Skein cannot restrict parts of a repository. Material that must be restricted (export-controlled, proprietary) goes in a repository of its own, linked as section 10.5 describes.

## 2. Principles

1. **Plain text in git is the source of truth, with no database.** Every item, link, review, baseline, schedule, date, estimate and allocation Skein holds is in files under version control, so it can be edited offline, with any editor or tool, and reviewed and merged like code. What a forge already holds (an issue's state, assignees, labels) stays sourced there and is not duplicated (section 10.4). Everything else is generated.
2. **Forge-neutral.** Skein works with nothing but a git repository. Integrations with GitHub, GitLab and Forgejo are adapters; the core never relies on a feature one of the three lacks (section 7).
3. **Schema-driven.** A project declares its item types, their attributes, the links allowed between them and the rules they must satisfy. Skein has no built-in notion of "requirement" or "test".
4. **Prose-friendly.** An item can be a file of its own or a paragraph inside a document, so a specification reads as a document while every paragraph stays an item.
5. **Cheap for people and agents.** Small text files, readable IDs, one obvious place for everything; no generated file is ever edited by hand.
6. **Deterministic.** The same inputs (the files, and the forge data where it is used) give byte-identical outputs, so generated files diff cleanly and CI can check them.
7. **One binary, one codebase.** Zig, built with the latest official release at the time of each Skein release (0.17.1 now), pinned per release (emanspeaks, 2026-11-21); no runtime dependencies, on Windows, Linux and macOS. Skein must be usable where outside dependencies need special approval, because a dependency that is downloaded and updated over the years is a supply-chain risk (emanspeaks, 2026-11-21). So nothing is fetched at build time or run time, and nothing is run as a separate tool: what Skein takes from other projects is copied into its repository as a fork that Skein maintains. Each piece is read before it goes in, recorded with its origin (project, commit) and license, and updated only on purpose, by a reviewed change.

## 3. Concepts

- **Project:** a git repository with a `.skein/` directory at its root. A project can span several repositories, one of which holds what they share (section 10.5).
- **Schema:** the project's item types, attributes, link types and rules.
- **Item type:** a kind of item, for example `need`, `srs`, `design`, `test` for a requirements set, or `proposal`, `rule`, `test` for a language specification. A type declares its ID pattern, its attributes, which links it may or must have, and its categories if any (for a specification's rules: syntax, legality, dynamic semantics, implementation-defined, undefined, informative).
- **Item:** one identified piece of text with a type, attributes and links. Its **fingerprint** is a hash of its normative content (text and attributes the schema marks as normative), used to detect change. The content is normalized first (line endings, runs of white space, wrapping), so reformatting a file changes no fingerprint.
- **Status:** every item has one, from a lifecycle the schema declares (for example draft, approved, deprecated, removed). A removed item leaves a tombstone, so its ID is never used again and old citations of it can be explained.
- **Link:** a typed, directed reference from one item to another (`derives-from`, `implements`, `verifies`, `introduced-by`, ...). Skein records the fingerprint of its target when it was last reviewed (section 6); when the target changes, the link becomes **suspect** until someone reviews it again.
- **Document:** an ordered, readable assembly of items and narrative text (a specification chapter, an SRS, a design description). Narrative text is not an item and carries no obligations.
- **Citation:** a reference to an item from outside the item files: a test that says which rules it checks, a source file that says which requirement it implements, a commit or pull request that names an item.
- **Result:** the outcome of a test for an implementation, imported from a test run, attached to the items the test cites.
- **Verification record:** evidence that an item is satisfied by a method other than an automated test (analysis, inspection, demonstration, a manual test procedure that was run): who, when, of which version, with what outcome, and where the evidence is.
- **Approval:** a record in git that a named person approved an item at a given fingerprint (section 6).
- **Profile:** a named selection of items (for example one stage of a language that is defined in stages, or a software class of NPR 7150.2D), for which documents, coverage and compliance can be produced separately.
- **Baseline:** a named, immutable state of the item graph, against which changes and coverage are compared: a git tag (section 6).

## 4. Sources

### 4.1 Configuration and schema

A `.skein/` directory at the repository root holds Skein's own files (emanspeaks, 2026-11-21): the configuration (item directories and documents, the schema, citation patterns, outputs, the forge and the other repositories of the project), and the data that belongs to no item file and that the forge does not hold, such as reviews of links, resources and calendars, time logs, schedules and the planning data the forge cannot store for an issue, and planning overlays (section 10.4). Items and documents themselves live wherever the project wants them (`docs/`, `spec/`, beside the code); `.skein/` is for Skein's bookkeeping. Its files and the front matter of items are TOML (emanspeaks, 2026-11-21): simple enough for Skein to parse with its own code, with real date and time types for schedules, and readable by other tools. Deep nesting, where TOML is awkward, is avoided by keeping one thing per file (one person, one item type, one mirrored issue).

### 4.2 Item files

An item of its own is a Markdown file with a front-matter block (ID, type, attributes, links) and a body. This is close to Doorstop's Markdown items, so Doorstop trees can be converted mechanically (section 11).

### 4.3 Paragraph items in documents

In a document, any paragraph or list item can be an item by carrying a marker with its ID and, where the type has categories, its category. Links and attributes go in a compact form after the marker or in a short block below the paragraph. The marker comes first, at the start of the paragraph or list item or on a line of its own before it (emanspeaks, 2026-11-21), in the manner of the Rust Reference (`r[lex.comment.line]`): with one line per paragraph, a marker at the end of the line would be out of sight. It is spelled `%type[id words]`, where a bare word is the category or the status; the percent sign makes it stand out and keeps prose such as `array[i]` from being one. It is plain text, cheap to type, readable in a raw view on any forge, and easy to find with grep. A list entry with a marker, in a list that belongs to an item, is a part of that item. A part is an item in its own right, and its ID may extend the ID of the containing item (`%rule[.as]` in `lex.keywords` is `lex.keywords.as`). The content of the containing item includes the content of its parts: its fingerprint covers the name and fingerprint of each part, like a tree in git (section 6), and for coverage it counts as covered when it is covered itself or when all its parts are. IDs are readable and hierarchical (`lex.comment.line`, `expr.as.narrow`), as in the Rust Reference, or numbered (`SRS-012`), as Doorstop's are; the scheme is chosen per item type in the schema (emanspeaks, 2026-11-21). They are never random.

### 4.4 Citations in code and tests

Comments in source and test files cite items, with a configurable pattern per file type (for example `// spec: expr.as.narrow` in a conformance test, `/// Implements SRS-012.` in a Zig doc comment). A directory can carry a file that cites items for every test inside it. Skein checks that every citation names an existing item of an allowed type.

Later: code examples inside documents can be marked as tested, and `skein` extracts them for the project's own test driver, so the examples in a specification cannot go stale.

### 4.5 Results and verification records

Skein imports test results in common formats (JUnit XML, TAP, and a small native JSON format for test drivers that write their own), records which implementation and version produced them, and attaches them to the items the tests cite.

Not everything is verified by an automated test. The schema can give an item a verification method (test, analysis, inspection, demonstration), and a verification record, a small file written by hand or through the VS Code extension, supplies the evidence for the other methods and for manual test procedures. `coverage` counts an item as verified by whichever its method requires.

### 4.6 References in prose

Text refers to items inline: a rule cites another rule, a sentence uses a defined term, a requirement points at a design element. An inline reference is a marker without a type (emanspeaks, 2026-11-21): `%[id]`, or `%[id words]` to show the words in place of the ID. It leaves the double brackets of wikis and site generators to those tools. `check` verifies every one, the renderer turns them into links and builds each item's "referenced by" list, and renaming an ID updates them. Defined terms are items of a type the schema declares, so a glossary is a filtered list.

### 4.7 External standards

A standard the project must comply with (NPR 7150.2D's requirements, a coding standard, a customer's specification) is an item set of its own: read-only, kept in its own repository or directory, imported once from its source (CSV to begin with) and versioned. Project items link to its items, so a compliance matrix is an ordinary trace view. Applicability is by profile (a software class), and tailoring, waivers and deviations are item types the schema declares, linked to the requirement they relax, with their rationale and approval.

## 5. The engine

A command-line tool, `skein`, with subcommands that each do one thing and fail with clear messages and a nonzero exit status:

| Command | Does |
| --- | --- |
| `check` | Validates the configuration, the schema, every item and link, every citation; reports duplicate, unknown and malformed IDs, missing required links, suspect links. The command CI runs. |
| `trace <id>` | Shows an item with everything above and below it, as text or JSON. |
| `coverage` | Reports, per item type and per category, which items lack the links or citations the schema expects (for example rules without tests), and the results per implementation. |
| `review <id>` / `clear <id>` | Records that an item, or the links to a changed parent, have been reviewed, by updating the stored fingerprints. |
| `approve <id>` | Records an approval of an item at its current fingerprint (section 6). |
| `diff <ref> [<ref>]` / `impact` | Shows which items were added, changed or removed between two commits or baselines, and what a change reaches: the items downstream, the links it makes suspect, the tests to run again. Text, JSON, or a summary for a pull request. |
| `baseline <name>` | Freezes a baseline: writes what a tag alone would not hold, commits and tags (section 6). |
| `new` / `move` / `link` | Creates items with the next free ID, renames IDs (keeping an alias), adds links; keeps files consistent so no one edits fingerprints by hand. |
| `apply` | Writes a planning overlay's values to the forge and removes them from `.skein/` (section 10.4). |
| `mirror` / `sync` / `publish` | Copies the forge's data into a full plain-text mirror, writes offline edits back to the forge, and re-creates mirrored data on another forge (section 10.4). |
| `import` | Converts Doorstop trees; imports items from CSV (requirements from a spreadsheet or a DOORS export, an external standard); imports test results. |
| `export` | Writes the whole graph as JSON (for other tools and agents) and any matrix or list as CSV, and ReqIF for interchange with DOORS and similar tools. |
| `render` | Builds the site, and each document as a single file for delivery (section 8). |
| `lsp` | The language server (section 9). Later. |

The graph is built from the files on every run; for large projects a cache under the build directory may speed it up, but deleting it changes nothing.

## 6. Change, review and baselines

- Every item has a fingerprint over its normative content. For each link, Skein records the fingerprint of the target as last reviewed; a changed target makes the link suspect, and `check` reports it until `clear` records the review.
- Review records are kept in `.skein/`, never in the items or beside the documents (emanspeaks, 2026-11-21), so sources hold no hashes and document folders hold no extra files. Under `.skein/reviews/` there is one file per document or item directory, with one sorted line per link, so two branches conflict only where both reviewed the same document. Skein writes these files; no one edits them by hand.
- **Baselines are git tags**; `check`, `coverage` and `diff` can compare against one ("what changed since v0.3", "which rules are new and untested"). A tag freezes everything that is in git. The only thing it does not freeze is a value the forge holds (an issue's due date or milestone), so where a plan uses such values, `skein baseline` first writes them to a file under `.skein/baselines/`, commits it, and tags that commit. A project with no forge data in its plan just tags.
- **Approvals are in git** (emanspeaks, 2026-11-21): who approved which item, when, and at which fingerprint, under `.skein/` like the review records. `skein approve` writes one; the forge adapter can also write them from a merged pull request's approvals, so the forge's review is the act and git keeps the record. They survive a move to another forge and can be shown to an auditor. An item whose content changed after its approval is reported as no longer approved, and the schema can require approval for a status (no `approved` requirement without one).
- **IDs are never reused.** `check` reports an ID that a tombstone holds, and two branches that took the same new number are caught when they meet, with `skein move` to renumber one.
- **History as data:** counts over time (items by status, changes per baseline, coverage) come from git history the same way burndown does (section 10.3), for the measurement reports that standards such as NPR 7150.2D ask for. Later.

## 7. Forges

The core needs only git. Everything that involves a forge goes through an adapter with one small interface, implemented for GitHub first, then GitLab and Forgejo:

- Resolve an item's links to issues and pull or merge requests (references written in item attributes or commit messages).
- Read the reviews and approvals of a merged change, to record them in git (section 6).
- Read and write the planning fields its forge stores (section 10.4).
- Report `check` and `coverage` results in CI in the forge's format (annotations, summaries).

Forge data is read live (emanspeaks, 2026-11-21): views and checks that use it follow the forge as it changes, and without a connection they use the last values read, or the mirror, and say so. Skein's output is still determined by its inputs: the same files and the same forge data give the same bytes.

A capability that only one forge has (for example GitHub Projects fields or issue types) may be used by that adapter for convenience, but Skein's own features never depend on it. Acceptance of a proposal or a design change is a merge, which all three forges have.

## 8. Rendering

`skein render` builds the site itself: documents with every item anchored by its ID, generated matrices, coverage pages, per-item backlinks, filtered lists, schedules and charts, as static HTML that needs no server. Rendering is part of the one codebase (principle 7), not a separate tool (emanspeaks, 2026-11-21).

- **The renderer is forked from Zine** (MIT) and merged in (emanspeaks, 2026-11-21), copied in piece by piece as Skein needs it rather than all at once. Zine 0.14.1 builds on about a dozen other projects (SuperMD, SuperHTML, Ziggy and Scripty by the same author; a C Markdown parser, cmark-gfm; an image library, a syntax highlighter, a time library and more), and Skein expects to take most of them in time, each under the rule of principle 7.
- **The Markdown parser** is the first piece, since Skein must parse Markdown in any case to find paragraph items. cmark-gfm can stay as C code that Zig compiles, be converted to Zig, or be replaced by a parser of Skein's own; all three are acceptable, and the choice is made when that code is written.
- The output is plain HTML and CSS; `skein render` can also write plain Markdown pages for another site generator.
- Search, backlinks and a broken-reference check are Skein's own, built from the graph.
- **Documents for delivery:** each document can also be rendered as one self-contained HTML file with a print style sheet (title page, numbered sections, page headers, a change record from the baselines), which any browser prints to PDF. Projects that hand over documents, as NPR 7150.2D work does, need this more than a site.
- **Profiles and editions:** a document or the whole site can be rendered for one profile (only what applies to one stage, or to one software class), and for several baselines side by side (`render --editions`), so readers can pick the edition that matches a release.
- **Charts and diagrams that Skein computes** (trace graphs, Gantt charts, burndown and burnup, resource load) are drawn by Skein itself as static SVG, so they are deterministic, diff cleanly, and need no JavaScript or outside tool.
- **Mermaid** blocks written by hand in documents (flowcharts, sequence and state diagrams) are kept as they are. VS Code and all three forges draw them in their own Markdown views; on the rendered site they are drawn by a copy of mermaid.js that is vendored in Skein's repository and shipped with the site (emanspeaks, 2026-11-21), never loaded from a content delivery network, and updated when Skein chooses. Mermaid's own command-line renderer is not used, since it needs Node.js and a headless browser. Skein can also export its own graphs as Mermaid source, for pasting into issues and pull requests, which all three forges render.

## 9. Interactivity

1. **A language server** (`skein lsp`) for the item and document sources in any editor: go to definition on an ID, find references, completion of IDs and link targets, hover previews, diagnostics from `check`, rename of an ID across files.
2. **A VS Code extension** on top of it is Skein's graphical interface (emanspeaks, 2026-11-21): the item tree, trace views, coverage, forms for items, and the interactive planning views (section 10), where dragging a bar in the Gantt chart or a card on a board writes the change to the item's file. The extension is thin, as a language-server extension should be: its TypeScript only connects VS Code to the `skein` binary, which holds the logic and draws the views, so other editors can use the same server. The packages an extension must take from npm are the one outside dependency that cannot be avoided for now; keeping the TypeScript to that connection keeps them to the minimum.
3. **No hosted application in the first scope.** People who edit (authors, project managers) have VS Code; everyone else reads the rendered documents, schedules and charts, which are static files that any web server, or a file share, can serve. A hosted web interface that edits the same files is a backlog feature (emanspeaks, 2026-11-21).

## 10. Planning

Skein plans and tracks the work as well as describing the product, taking from OpenProject the parts that matter: work packages with dates and dependencies, Gantt charts, boards, burndown, resource management, and comparing a plan with a baseline. The difference from OpenProject is the same as everywhere else in Skein: the plan is files in git, not a database.

### 10.1 Work items

- Work is items of types the schema declares (for example `epic`, `task`, `milestone`), with planning attributes: status, start and finish dates or a duration, estimated and remaining effort, assignees, priority, and the version or milestone they belong to.
- Work items link to each other (parent and child; `precedes`/`follows` with a lag; `blocks`) and to the product items they serve (`implements` a requirement, `verifies` a rule), so a Gantt bar can be traced to the requirements behind it, and a requirement's coverage can show the work still open on it.
- **Scheduling:** an item is scheduled automatically from its predecessors and its duration, or by hand with fixed dates, as OpenProject's two modes are. Skein computes the schedule, the critical path and the slack, and `check` reports what cannot be met: a date before a predecessor's finish, a child outside its parent, a milestone the plan misses.
- **Time spent:** effort logged against an item (who, when, how long) is kept in files beside it, for actual-versus-estimate reports.

### 10.2 Resources

- A resources file lists the people (and, where wanted, roles or teams), each with a capacity (hours per week, or a share of full time) and a calendar of working days, holidays and absences. It lives in `.skein/`, in the planning repository when the project has several (section 10.5).
- From assignments and effort Skein computes each person's load per week, shows it next to their capacity, and reports overallocation in `check` and as a chart.
- People are identified by a handle the project chooses (for example their forge user name), mapped per forge by the adapter, so a plan moves between forges unchanged.

### 10.3 Views

- **Gantt chart:** bars, milestones, dependencies and the critical path, by version, by person, or for any filter; with a baseline's bars beside the current ones to show slippage.
- **Burndown and burnup** per milestone, version or iteration, modeled on GitLab's charts (emanspeaks, 2026-11-21), which GitLab offers only in its paid tiers. Over the milestone's dates, day by day: the burndown shows what remains, against a straight guideline from the starting total to zero; the burnup shows the total scope and what is completed, so work added or removed during the milestone is visible instead of looking like lost progress. Both count either items or weight (effort). They are built from events, as GitLab's are: an item added to or removed from the milestone, closed or reopened, its weight changed. Events come from where each value lives: the forge's issue events for what the forge holds, and git history on the main branch for what Skein holds; so nothing records snapshots by hand and a chart can be rebuilt for any past milestone.
- **Boards** by status, assignee or version, and a **roadmap** of versions with what each contains and how far along it is.
- **Resource load** per person and week, as a table and a chart.
- The same filters as everywhere else ("open tasks implementing chapter 4", "work on rules with no test"), as pages and in `skein export`.

### 10.4 Forge issues

Discussion stays in the forge, so a work item can be linked to an issue, and an issue can be a work item of its own without a separate file. Skein wraps the forge's data instead of copying it (emanspeaks, 2026-11-21):

- **The forge is the truth for what it holds.** What it holds depends on the forge: GitHub, GitLab and Forgejo differ in milestones, due dates, weights, dependencies, time tracking and custom fields. Each adapter declares which planning fields its forge stores, and Skein reads those through it.
- **`.skein/` holds only what the forge lacks:** schedules, allocations, lags, capacity, links to milestones or work outside git, and whatever field the chosen forge cannot store. It is keyed by the issue's reference and never repeats a value the forge holds, so with a richer forge `.skein/` holds less. Moving to another forge moves a field between the two sides; `skein` writes the fields the new forge lacks into `.skein/` as part of the move.
- **No mirror by default.** Values read from the forge are cached under the build directory, derived and deletable, so the last view of them is available offline; nothing of them is committed except as below, or when a full mirror is chosen. Charts that need the history of forge-held fields (a burndown of closed issues) read it from the forge's issue events, which all three forges keep.
- **Baselines** are the exception: `skein baseline` writes the forge-held values a plan uses (for example due dates, at the moment a version's plan is frozen) into git before tagging (section 6), a deliberate, named snapshot rather than a running copy.

#### Overlays and what-if plans

A branch of the plan can explore a different schedule: other priorities, assignments, dependencies or dates. Changes to what Skein holds are ordinary edits on the branch. Changes to what the forge holds are kept as an **overlay**, copy on write: `.skein/` records only the fields that deviate, each with the upstream value it was based on, and everything else still comes from the forge.

- `check` reports an overlay whose upstream value has since changed, as a merge would report a conflict.
- Views and charts on the branch show the plan with the overlay applied, and can show it beside the current plan.
- When the plan is adopted, `skein apply` writes the overlay's values to the forge through the adapter and removes them from `.skein/`; a plan that is not adopted is a branch that is never merged.
- The same mechanism releveling uses: Skein proposes reassignments or new dates to remove overallocation as an overlay, for review like any other change.

#### Full mirror and moving between forges

When it is needed, a project or one person can opt into a **full mirror** of the forge's data (emanspeaks, 2026-11-21), for two purposes:

- **Extended offline work.** `skein mirror` copies everything the forge holds for the project's issues and milestones (every issue and milestone in full: fields, labels, relations and comments, and the reviews and approvals of pull or merge requests; emanspeaks, 2026-11-21) into a forge-neutral plain-text form, in `.skein/mirror/`. Offline, the mirror stands in for the forge: views, `check` and edits work as if it were there. Edits to mirrored values are recorded the same way as overlays, each with the value it was based on. Back online, `skein sync` writes them to the forge, refreshes the mirror, and reports each field that changed on both sides for a decision rather than overwriting either.
- **Moving between forges.** The mirror is the interchange format: `skein mirror` from the old forge and `skein publish` to the new one, each through its adapter, re-create the issues, labels, milestones and relations, with comments where the target allows. Fields the new forge cannot store move into `.skein/`, so nothing is lost, and fields it can store move out of `.skein/` into the forge. A map from old references to new ones (`github:#24` to `forgejo:#24`) is kept in `.skein/`, so citations in items, code and commits keep resolving.

The mirror is per checkout by default (ignored by git, rebuilt by `skein mirror`), so the default of no duplication in the repository holds. A project can choose to commit it instead, for a team working offline together or to keep an archive that outlives the forge; then the mirror is the truth while offline, and `skein sync` is how it gives that back.

`skein` can also create or update issues from items. Projects that do not want issues use items alone.

### 10.5 Projects of several repositories

A project spread over several repositories (a compiler, a website, an editor extension) can have one **planning repository** that holds what they share: the resources and calendars, work that spans repositories (milestones, roadmaps, epics), and the cross-repository views.

- Each repository's `.skein/` names the planning repository, and the planning repository's names the others, by a short project name and a location: a path to a local checkout (a sibling or a submodule) or a remote URL. The repositories can be on different forges.
- **Issues, milestones and pull requests** in other repositories are cited by a qualified reference (`editor#24`). They are forge objects, so they are resolved live through the adapter like the repository's own, with nothing to pin (emanspeaks, 2026-11-21).
- **Items, code and tests** in other repositories are things in git, cited by a qualified reference (`compiler:expr.as.narrow`) and tied to a commit. The items of all the repositories form one network, with a fingerprint of its own, a hash tree over each repository's items as an item's is over its parts. A state of the network is one commit per repository (emanspeaks, 2026-11-21): the project that declares the others is the root of their network and records the state, in a file Skein writes (`.skein/network.toml`), and a commit of the root that changes it is a new state of the network. By default, Skein reads every repository at the recorded state and moves from one recorded state to the next; the states between can be looked at on request (`--current`: each at the commit checked out; `--working`: as the files are), where links may be broken.
- Networks nest: a compiler can be the root of its own, a website of one that includes the compiler, and a workspace of one that includes both. A repository is known by an identity of its own, which it declares, not by the short name a network gives it, so the same repository reached by two paths is one; the root's record holds every repository reached, each once, at one commit, and the project Skein is run for decides. A member that is a git submodule of the root is recorded by git itself.
- Repositories are found by a path (a checkout on disk) or a URL that Skein fetches with git into a cache under `.git/`. Fetching is the default; offline (`--offline`, or a fetch that times out) references into a repository that cannot be read are unresolved: a warning, not an error. A reference whose target does not exist at the recorded state is an error, and `render` shows an unresolved one as its words, marked as unresolved.

## 11. Migration

- **Doorstop:** `skein import doorstop` converts a Doorstop tree (items, links, reviewed fingerprints, `references`) into Skein items and a schema, so a project can switch without losing history or reviews.
- **Existing prose:** a specification or reference already written as Markdown pages is brought in by adding markers to its paragraphs, and existing tests by adding citations, a chapter at a time; what is not yet marked stays narrative text.

## 12. Phases

1. **This design**, accepted by merge.
2. **Core and CLI:** configuration and schema, item files and paragraph items, references in prose, statuses and tombstones, citations, profiles, `check`, `trace`, `coverage`, `review`/`clear`, `approve`, `diff` and `impact`, `export` (JSON, CSV), `import` (Doorstop, CSV). Proven on one chapter of a language specification with its tests, and on an import of an existing set of Doorstop trees. From here, Skein's own requirements are written in Skein.
3. **Rendering and results:** `render` (site and documents for delivery), result import and verification records, external standards and compliance matrices, baselines, the forge adapter for GitHub with CI output.
4. **Planning, first part:** work items, scheduling and the critical path, Gantt, burndown and burnup, boards and the roadmap as rendered pages; the GitHub adapter's planning fields. Proven on Skein's own work and on one other project's roadmap.
5. **Editing:** `new`/`move`/`link`, the language server, the VS Code extension with forms and interactive planning views.
6. **Planning, second part:** resources, calendars and load, time spent, releveling, overlays and `skein apply`.
7. **Wider:** GitLab and Forgejo adapters, the full mirror with `sync` and `publish` between forges, ReqIF export, tested examples, editions side by side, measurements over time. Backlog: a hosted web interface.

## 13. Open questions

Nothing is waiting on a decision. Left to settle with the first code, and to bring to emanspeaks then: the names inside `.skein/` (for example `config.toml`, `resources.toml`, `overlay/`), and the spelling of the paragraph marker and of references in prose.

## 14. Requirements of Skein itself

Skein's requirements are written in Skein's own format, in `docs/requirements/`: what it does today, each requirement cited by the tests that check it, and, more coarsely, what this document commits it to and the code does not do yet (`status=planned`). `skein check` and `skein coverage --profile implemented`, run in Skein's repository, say whether they hold together; CI runs both. This document stays the description of where Skein is going and why; where the two disagree about what Skein does, the requirements are right and this document is to be brought in line.
