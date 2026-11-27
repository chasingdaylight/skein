//! The command line: which command the arguments ask for.

const std = @import("std");

const Network = @import("network/Network.zig");
const Project = @import("Project.zig");
const Approvals = @import("graph/Approvals.zig");
const Results = @import("results/Results.zig");

pub const usage =
    \\Usage: skein <command> [options]
    \\
    \\Commands:
    \\  check             Check the project: its configuration, schema and items
    \\  trace ID          Show an item with what is above and below it
    \\  coverage          Count the items that are linked to or cited as expected
    \\  diff [REV [REV]]  Show the items added, removed or changed since a commit
    \\  impact [REV]      Show what the changes since a commit reach
    \\  export [WHAT]     Write the graph as JSON, or items, links or citations as CSV,
    \\                    gitlab-requirements: a CSV for GitLab's requirements import,
    \\                    or reqif: ReqIF 1.2, for DOORS and other requirements tools
    \\  render --out DIR  Write the documents as Markdown for a site generator
    \\  serve [--port N]  Serve the site, rendered as the files change, and edit it
    \\                    there: on this computer, or for a team with --sign-in
    \\  move OLD NEW     Give an item another ID, everywhere the old one is used
    \\  new TYPE [ID]     Start an item: its file, or the marker for a document
    \\  link FROM TYPE TO Add a link of a type from one item to another
    \\  baseline [NAME]   Tag what is committed as a baseline; without NAME, list them
    \\  init [--template NAME]... [--option NAME=VALUE]...
    \\                    Start a project here, from templates' document skeletons
    \\  template list     The templates built into skein
    \\  template show NAME
    \\                    What a template declares, and its options
    \\  template eject NAME
    \\                    Write a template's files into .skein/, to change them
    \\  template documents
    \\                    Write the document skeletons of the templates in use that
    \\                    are not in docs/ yet, those brought along by options too
    \\  examples --out DIR
    \\                    Write the tested examples as files, with an index, for
    \\                    the project's own test driver
    \\  pin [NAME [REV]]  Record the commits of the other repositories that the items
    \\                    are checked against (default: what each has checked out)
    \\  import doorstop DIR...
    \\                    Turn Doorstop documents into skein items, in place
    \\  import csv FILE --type TYPE --to DIR
    \\                    Make an item file in DIR of each row of a CSV file
    \\  import reqif FILE --type TYPE --to DIR
    \\                    Make an item file in DIR of each spec object of a ReqIF file
    \\  import jama PROJECT --jama-type KEY --type TYPE --to DIR
    \\                    Make an item file in DIR of each item of a Jama Connect
    \\                    project, through its REST API
    \\  import gitlab-requirements FILE
    \\                    Record the GitLab requirement of each item, from the CSV
    \\                    GitLab exports of a project's requirements
    \\  review ID...      Record the links of these items as reviewed
    \\  clear ID...       Record the links to these items as reviewed
    \\  approve ID...     Record an approval of these items as they are now
    \\  result ID pass|fail|skip
    \\                    Record a result a person obtained, such as a procedure
    \\                    carried out by hand, in the results the project keeps
    \\  schedule          Schedule the work items, and write .skein/schedule.toml
    \\  gitlab-requirements [--profile NAME] [--dry-run]
    \\                    Bring the project's GitLab requirements to its items, through
    \\                    GitLab's API: create, update, archive; and keep the map
    \\  jama [--profile NAME] [--dry-run]
    \\                    Bring a Jama Connect project's items to the items, through
    \\                    its REST API (.skein/jama.toml): create, update, relate
    \\  level [--write]   Move work later so that nobody has more work than time; list
    \\                    the moves, or write them into the work items
    \\  time [ITEM HOURS] Log hours spent on a work item; without them, spent against estimate
    \\  overlay [ISSUE FIELD VALUE]
    \\                    A what-if plan's deviations from the forge: list, record or --remove
    \\  apply             Write the overlay to the forge, and take it out (--dry-run, --force)
    \\  mirror            Copy the forge's issues, milestones and labels into .skein/mirror/
    \\  sync              Write the overlay to the forge, then refresh the mirror
    \\  publish --to KIND:OWNER/REPO
    \\                    Re-create the mirror on another forge (--url, --dry-run)
    \\  rewrite-refs      Write the new numbers into references to a former forge's issues (--dry-run)
    \\  load              Each person's work, week by week, beside the time they have
    \\  api GET|POST PATH [QUERY]
    \\                    One of skein serve's editing requests, its body on standard
    \\                    input: how the static site's edit mode asks (render --edit)
    \\  lsp              Serve editors as a language server, on standard input and output
    \\  mcp               Serve AI agents skein's tools (Model Context Protocol), on
    \\                    standard input and output
    \\  agents [--skill]  Write what coding agents should know of Skein into AGENTS.md
    \\                    (or CLAUDE.md, or --file PATH), or as a skill file
    \\  help              Show this text
    \\  version           Show skein's version
    \\
    \\Options:
    \\  --root DIR        The project, or a directory inside it (default: here)
    \\  --json            trace, coverage, diff, impact, load, time: as JSON
    \\  --markdown        coverage, diff, impact: as Markdown, for a pull request
    \\  --profile NAME    coverage, export, render: only the items of this profile
    \\  --current         check, trace, coverage, export, render: read the other
    \\                    repositories at the commit each has checked out, not the
    \\                    one pinned
    \\  --working         the same, with their files as they are, committed or not
    \\  --offline         the same commands, and pin: fetch nothing; a repository
    \\                    by url is read from what its cache holds
    \\  --results FILE    trace, coverage, render: test results besides the project's own
    \\                    (TOML, JSON, YAML, JUnit XML or TAP); may be given more
    \\                    than once
    \\  --alias, --no-alias
    \\                    move: keep the old ID as an alias, or not (default: kept
    \\                    when the project declares an id, so others can cite it)
    \\  --all             review, clear: every link, not those of the items named
    \\  --from-pull-request N
    \\                    approve: the approvals merged pull request N had in review,
    \\                    of what it changed
    \\  --option NAME=VALUE
    \\                    init: a template's option; may be given more than once
    \\  --as ROLE         approve: the role the approval is given in, where the type
    \\                    names the roles that must each approve
    \\  --sign            approve: commit the approval, signed with your key (git's
    \\                    user.signingkey: OpenPGP, SSH, or an X.509 certificate)
    \\  --by NAME         approve, result, time: who (default: git's user.name)
    \\  --on DATE         approve, result, time: when, as 2027-03-01 (default: today)
    \\  --note TEXT       result, time: what to keep with it
    \\  --evidence PATH   result: a file that shows it; may be given more than once
    \\  --implementation NAME
    \\                    result: what produced it; trace, coverage, render: what
    \\                    produced the results of --results that name nothing
    \\  --implementation-version VERSION
    \\                    trace, coverage, render: its version
    \\  --gitlab-requirements FILE
    \\                    coverage: also write GitLab's requirements report, for a CI
    \\                    job's artifacts
    \\  --type TYPE       import csv, reqif, jama: the item type of the rows
    \\  --to DIR          import csv, reqif, jama: where the item files go
    \\  --id-column NAME, --text-column NAME
    \\                    import csv: the columns of the IDs and the text
    \\                    (default: id, text)
    \\  --replace         import csv, reqif, jama: write over item files that are there
    \\  --jama-type KEY   import jama: the Jama item type to take (REQ)
    \\  --headings-as-text
    \\                    import doorstop: non-normative items as plain Markdown
    \\  --status-from NAME, --verification-from NAME
    \\                    import doorstop: the attribute that gives the status,
    \\                    or the verification method
    \\  --port N          serve: the port (default 8080)
    \\  --listen ADDR     serve: the address to listen on (default 127.0.0.1); another
    \\                    needs --sign-in and --url
    \\  --url URL         serve: the address people reach it at, behind a proxy
    \\  --sign-in proxy|forge|oidc
    \\                    serve: people sign in through a reverse proxy's header, the
    \\                    project's forge, or an OpenID Connect provider (--issuer
    \\                    URL); the last two with SKEIN_OAUTH_CLIENT_ID and _SECRET
    \\  --user-header NAME, --email-header NAME
    \\                    serve --sign-in proxy: the headers that name the person
    \\                    (default X-Forwarded-User, X-Forwarded-Email)
    \\  --proxy IP        serve --sign-in proxy: an address the proxy connects from
    \\                    (default this computer's); may be given more than once
    \\  --out DIR         render, examples: where the files go
    \\  --format NAME     render: markdown for a site generator (the default),
    \\                    html: the site itself, or document: one file per document;
    \\                    check: text (the default), github: annotations for
    \\                    GitHub Actions, or gitlab: a Code Quality report
    \\  --editions        render: each baseline too, under editions/NAME/, with
    \\                    a page that lists them
    \\  --edit --wasm FILE
    \\                    render --format html: pages that edit the files, with skein
    \\                    built for WebAssembly (zig build wasm) running in them
    \\  --controlled      render --format document: only the controlled documents,
    \\                    named ID-REVISION.html, with documents.tsv listing them
    \\
;

pub const Command = union(enum) {
    help,
    version,
    check: Check,
    trace: Trace,
    coverage: Coverage,
    load: Load,
    schedule: Schedule,
    level: Level,
    gitlab_requirements: GitlabRequirements,
    jama: GitlabRequirements,
    time: TimeSpent,
    overlay: OverlayCommand,
    apply: Apply,
    mirror: Mirror,
    sync: Sync,
    publish: Publish,
    rewrite_refs: RewriteRefs,
    /// `diff`, and `impact`
    diff: Diff,
    /// `export`
    exporting: Export,
    render: Render,
    serve: Serve,
    /// one of `skein serve`'s editing requests (`skein api`), for the static site's edit mode
    api: Api,
    move: Move,
    new: New,
    link: Link,
    baseline: Baseline,
    pin: Pin,
    examples: Examples,
    template: TemplateCommand,
    init: Init,
    /// the language server
    lsp,
    /// the Model Context Protocol server, on the project at the root given
    mcp: []const u8,
    agents: Agents,
    import: Import,
    review: Review,
    clear: Review,
    approve: Approve,
    result: Result,
    /// the first argument, which names no command
    unknown: []const u8,
    /// what is wrong with the arguments of a command
    misuse: []const u8,
};

/// The options every command that works on a project takes
pub const Common = struct {
    /// where to look for the project from
    root: []const u8 = ".",
    /// which state of the other repositories to read
    state: Network.State = .recorded,
    /// fetch nothing; repositories by url are read from their caches
    offline: bool = false,
    /// files read as given here, not as they are on disk (`skein serve`)
    unsaved: []const Project.Unsaved = &.{},
};

pub const TemplateCommand = struct {
    common: Common = .{},
    what: What,
    name: ?[]const u8 = null,

    pub const What = enum { list, show, eject, documents };
};

pub const Init = struct {
    /// the directory to start the project in
    root: []const u8 = ".",
    /// the templates it uses; an overlay goes with the template it overlays
    templates: []const []const u8 = &.{},
    /// the templates' options, as `NAME=VALUE`
    options: []const []const u8 = &.{},
};

pub const Check = struct {
    common: Common = .{},
    format: Format = .text,

    pub const Format = enum {
        /// `file:line:column: error: message`, on standard error
        text,
        /// GitHub Actions workflow commands, on standard output
        github,
        /// a GitLab Code Quality report, on standard output
        gitlab,
    };
};

pub const Pin = struct {
    common: Common = .{},
    /// the repository; all of them when null
    name: ?[]const u8 = null,
    /// the commit to record; what the checkout has checked out when null
    revision: ?[]const u8 = null,
};

pub const Trace = struct {
    common: Common = .{},
    id: []const u8,
    json: bool = false,
    /// results files besides the project's own, and what produced them
    results: Results.Given = .{},
};

pub const Coverage = struct {
    common: Common = .{},
    profile: ?[]const u8 = null,
    json: bool = false,
    /// as Markdown, for a job summary or a pull request
    markdown: bool = false,
    /// results files besides the project's own, and what produced them
    results: Results.Given = .{},
    /// where to write GitLab's requirements report
    gitlab_requirements: ?[]const u8 = null,
};

pub const Load = struct {
    common: Common = .{},
    json: bool = false,
};

/// `gitlab-requirements` and `jama`: the items published to another tool
pub const GitlabRequirements = struct {
    common: Common = .{},
    profile: ?[]const u8 = null,
    dry_run: bool = false,
};

pub const Level = struct {
    common: Common = .{},
    /// write the moves into the work items
    write: bool = false,
};

pub const Schedule = struct {
    common: Common = .{},
};

pub const OverlayCommand = struct {
    common: Common = .{},
    /// the issue (`#12`), its field and the value; none of them to list
    issue: ?[]const u8 = null,
    field: ?[]const u8 = null,
    value: ?[]const u8 = null,
    remove: bool = false,
};

pub const Apply = struct {
    common: Common = .{},
    /// say what would be written, and write nothing
    dry_run: bool = false,
    /// write also what changed on both sides
    force: bool = false,
};

pub const Mirror = struct {
    common: Common = .{},
};

pub const Sync = struct {
    common: Common = .{},
    dry_run: bool = false,
    force: bool = false,
};

pub const Publish = struct {
    common: Common = .{},
    /// the forge to create it on, `kind:owner/repo`
    to: ?[]const u8 = null,
    /// the address of a server other than the public one
    url: ?[]const u8 = null,
    dry_run: bool = false,
};

pub const RewriteRefs = struct {
    common: Common = .{},
    dry_run: bool = false,
};

pub const TimeSpent = struct {
    common: Common = .{},
    /// the work item and the hours; neither for the report
    id: ?[]const u8 = null,
    hours: ?[]const u8 = null,
    by: ?[]const u8 = null,
    on: ?[]const u8 = null,
    note: ?[]const u8 = null,
    json: bool = false,
};

pub const Agents = struct {
    common: Common = .{},
    /// as a skill file, not a section of the instructions
    skill: bool = false,
    /// the file to write, in place of the usual one
    file: ?[]const u8 = null,
};

pub const Diff = struct {
    common: Common = .{},
    /// the commit to compare from (default: HEAD), and the one to compare
    /// to (default: the files as they are)
    revisions: []const []const u8 = &.{},
    /// also what the changes reach
    impact: bool = false,
    json: bool = false,
    markdown: bool = false,
};

pub const Examples = struct {
    common: Common = .{},
    /// the directory the examples go to, from where skein is run
    out: []const u8,
};

pub const Export = struct {
    common: Common = .{},
    what: What = .json,
    profile: ?[]const u8 = null,

    pub const What = enum {
        /// everything, as JSON
        json,
        /// as CSV: one row per item, per link, per citation
        items,
        links,
        citations,
        /// as CSV for GitLab's requirements import
        @"gitlab-requirements",
        /// ReqIF 1.2, for DOORS and other requirements tools
        reqif,
    };
};

pub const Baseline = struct {
    common: Common = .{},
    /// the name of the tag; null lists the baselines
    name: ?[]const u8 = null,
    message: ?[]const u8 = null,
};

pub const Link = struct {
    common: Common = .{},
    from: []const u8,
    type_name: []const u8,
    to: []const u8,
};

pub const New = struct {
    common: Common = .{},
    type_name: []const u8,
    /// the ID; for a numbered type, the next free one when null
    id: ?[]const u8 = null,
    /// the source of item files the item goes to
    to: ?[]const u8 = null,
};

pub const Move = struct {
    common: Common = .{},
    /// the ID the item has
    old: []const u8,
    /// the ID it is to have
    new: []const u8,
    /// whether the old ID is kept as an alias; when null, as the project's
    /// `id` says: kept when it has one, since others can then cite it
    alias: ?bool = null,
};

pub const Render = struct {
    common: Common = .{},
    /// the directory the rendered files go to, from where skein is run
    out: []const u8,
    format: Format = .markdown,
    /// only the items of this profile
    profile: ?[]const u8 = null,
    /// results files besides the project's own, and what produced them
    results: Results.Given = .{},
    /// --format document: only the controlled documents, named ID-REVISION
    controlled: bool = false,
    /// each baseline too, under editions/NAME/
    editions: bool = false,
    /// --format html: the edit mode, with skein for WebAssembly from this file
    wasm: ?[]const u8 = null,

    pub const Format = enum {
        /// Markdown for a site generator
        markdown,
        /// the site itself: HTML pages
        html,
        /// each document as one HTML file of its own, for delivery
        document,
    };
};

pub const Serve = struct {
    common: Common = .{},
    port: u16 = default_port,
    /// only the items of this profile
    profile: ?[]const u8 = null,
    /// results files besides the project's own, and what produced them
    results: Results.Given = .{},
    /// the address it listens on: this computer's own by default
    listen: []const u8 = "127.0.0.1",
    /// the address people reach it at, behind a proxy (`https://reqs.example.com`)
    url: ?[]const u8 = null,
    /// how people sign in; none on this computer alone
    sign_in: SignIn = .none,
    /// with `proxy`: the headers that name the signed-in user, and their email
    user_header: []const u8 = "X-Forwarded-User",
    email_header: []const u8 = "X-Forwarded-Email",
    /// with `proxy`: the addresses the proxy connects from (default: this computer)
    proxies: []const []const u8 = &.{},
    /// with `oidc`: the OpenID Connect provider
    issuer: ?[]const u8 = null,

    pub const default_port = 8080;

    /// Whether `ip` is this computer's own address
    pub fn loopback(ip: []const u8) bool {
        return std.mem.startsWith(u8, ip, "127.") or std.mem.eql(u8, ip, "::1");
    }

    pub const SignIn = enum {
        none,
        /// a reverse proxy signs people in and names them in a header
        proxy,
        /// the project's forge, through OAuth
        forge,
        /// an OpenID Connect provider (`--issuer`)
        oidc,
    };
};

pub const Api = struct {
    common: Common = .{},
    method: Method,
    /// under `/_skein/`, without it: `page`, `source`, `save`
    path: []const u8,
    query: []const u8 = "",

    pub const Method = @import("serve/guard.zig").Method;
};

pub const Import = struct {
    common: Common = .{},
    format: Format = .doorstop,
    /// from the project's root, with forward slashes: the directories of
    /// the Doorstop documents, or the CSV file
    paths: []const []const u8,
    /// csv: the item type of the rows
    item_type: ?[]const u8 = null,
    /// csv: the directory the item files go to
    to: ?[]const u8 = null,
    id_column: ?[]const u8 = null,
    text_column: ?[]const u8 = null,
    replace: bool = false,
    /// doorstop: non-normative items, which nothing links to, as plain
    /// Markdown: headings and introductions, which are narrative
    headings_as_text: bool = false,
    /// doorstop: the attribute whose values are the statuses
    status_from: ?[]const u8 = null,
    /// doorstop: the attribute whose values are the verification methods
    verification_from: ?[]const u8 = null,

    /// jama: the Jama Connect item type to take, by its key (`REQ`)
    jama_type: ?[]const u8 = null,

    pub const Format = enum { doorstop, csv, reqif, @"gitlab-requirements", jama };
};

pub const Review = struct {
    common: Common = .{},
    ids: []const []const u8 = &.{},
    all: bool = false,
};

pub const Approve = struct {
    common: Common = .{},
    ids: []const []const u8,
    by: ?[]const u8 = null,
    on: ?[]const u8 = null,
    /// the approvals of this merged pull request, in place of `ids`
    from_pull_request: ?u64 = null,
    /// the role the approval is given in, where the type names roles
    as: ?[]const u8 = null,
    /// commit the records, signed with the approver's key
    sign: bool = false,
    /// given in `skein serve`: how the approver was signed in
    signed_in: ?Approvals.SignedIn = null,
};

pub const Result = struct {
    common: Common = .{},
    id: []const u8,
    outcome: Results.Outcome,
    by: ?[]const u8 = null,
    on: ?[]const u8 = null,
    note: ?[]const u8 = null,
    implementation: ?[]const u8 = null,
    /// the files that show it
    evidence: []const []const u8 = &.{},
};

/// Every option, and whether a value follows it
const options = [_]struct { name: []const u8, takes_value: bool }{
    .{ .name = "--root", .takes_value = true },
    .{ .name = "--json", .takes_value = false },
    .{ .name = "--markdown", .takes_value = false },
    .{ .name = "--profile", .takes_value = true },
    .{ .name = "--all", .takes_value = false },
    .{ .name = "--by", .takes_value = true },
    .{ .name = "--on", .takes_value = true },
    .{ .name = "--type", .takes_value = true },
    .{ .name = "--to", .takes_value = true },
    .{ .name = "--id-column", .takes_value = true },
    .{ .name = "--text-column", .takes_value = true },
    .{ .name = "--replace", .takes_value = false },
    .{ .name = "--out", .takes_value = true },
    .{ .name = "--format", .takes_value = true },
    .{ .name = "--message", .takes_value = true },
    .{ .name = "--headings-as-text", .takes_value = false },
    .{ .name = "--status-from", .takes_value = true },
    .{ .name = "--verification-from", .takes_value = true },
    .{ .name = "--current", .takes_value = false },
    .{ .name = "--working", .takes_value = false },
    .{ .name = "--offline", .takes_value = false },
    .{ .name = "--alias", .takes_value = false },
    .{ .name = "--no-alias", .takes_value = false },
    .{ .name = "--results", .takes_value = true },
    .{ .name = "--note", .takes_value = true },
    .{ .name = "--implementation", .takes_value = true },
    .{ .name = "--implementation-version", .takes_value = true },
    .{ .name = "--gitlab-requirements", .takes_value = true },
    .{ .name = "--jama-type", .takes_value = true },
    .{ .name = "--editions", .takes_value = false },
    .{ .name = "--controlled", .takes_value = false },
    .{ .name = "--edit", .takes_value = false },
    .{ .name = "--wasm", .takes_value = true },
    .{ .name = "--write", .takes_value = false },
    .{ .name = "--from-pull-request", .takes_value = true },
    .{ .name = "--evidence", .takes_value = true },
    .{ .name = "--as", .takes_value = true },
    .{ .name = "--sign", .takes_value = false },
    .{ .name = "--template", .takes_value = true },
    .{ .name = "--option", .takes_value = true },
    .{ .name = "--remove", .takes_value = false },
    .{ .name = "--dry-run", .takes_value = false },
    .{ .name = "--force", .takes_value = false },
    .{ .name = "--skill", .takes_value = false },
    .{ .name = "--file", .takes_value = true },
    .{ .name = "--url", .takes_value = true },
    .{ .name = "--port", .takes_value = true },
    .{ .name = "--issuer", .takes_value = true },
    .{ .name = "--proxy", .takes_value = true },
    .{ .name = "--email-header", .takes_value = true },
    .{ .name = "--user-header", .takes_value = true },
    .{ .name = "--sign-in", .takes_value = true },
    .{ .name = "--listen", .takes_value = true },
};

/// The command `args` (without the program's name) ask for; help when
/// there are none. What it returns is allocated in `arena` or points
/// into `args`.
pub fn parse(arena: std.mem.Allocator, args: []const []const u8) std.mem.Allocator.Error!Command {
    if (args.len == 0) return .help;
    const name = args[0];
    if (eql(name, "help") or eql(name, "--help") or eql(name, "-h")) return .help;
    if (eql(name, "version") or eql(name, "--version")) return .version;
    if (eql(name, "lsp")) {
        // `--stdio` is what editors pass to pick the only transport there is
        for (args[1..]) |arg| {
            if (!eql(arg, "--stdio")) return .{ .misuse = "lsp takes no arguments" };
        }
        return .lsp;
    }

    var p: Parsed = .{ .arena = arena, .command = name };
    if (try p.read(args[1..])) |problem| return .{ .misuse = problem };
    if (p.flag("--current") and p.flag("--working")) return .{ .misuse = "give --current or --working, not both" };
    const common: Common = .{
        .root = p.value("--root") orelse ".",
        .state = if (p.flag("--working")) .working else if (p.flag("--current")) .current else .recorded,
        .offline = p.flag("--offline"),
    };
    const words = p.words.items;

    if (eql(name, "mcp")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "mcp takes no items" };
        return .{ .mcp = common.root };
    }
    if (eql(name, "agents")) {
        if (try p.allow(&.{ "--root", "--skill", "--file" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "agents takes no items" };
        return .{ .agents = .{ .common = common, .skill = p.flag("--skill"), .file = p.value("--file") } };
    }

    if (eql(name, "check")) {
        if (try p.allow(&.{ "--root", "--current", "--working", "--offline", "--format" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "check takes no items" };
        const format: Check.Format = if (p.value("--format")) |f| std.meta.stringToEnum(Check.Format, f) orelse
            return .{ .misuse = "check: the formats are text, github and gitlab" } else .text;
        return .{ .check = .{ .common = common, .format = format } };
    }
    if (eql(name, "template")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        const forms = "template: list, show NAME, eject NAME, or documents";
        if (words.len == 0) return .{ .misuse = forms };
        const what = std.meta.stringToEnum(TemplateCommand.What, words[0]) orelse return .{ .misuse = forms };
        if ((what != .list and what != .documents) != (words.len == 2) or words.len > 2) return .{ .misuse = forms };
        return .{ .template = .{ .common = common, .what = what, .name = if (words.len == 2) words[1] else null } };
    }
    if (eql(name, "init")) {
        if (try p.allow(&.{ "--root", "--template", "--option" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "init takes no items" };
        return .{ .init = .{ .root = p.value("--root") orelse ".", .templates = try p.values("--template"), .options = try p.values("--option") } };
    }
    if (eql(name, "examples")) {
        if (try p.allow(&.{ "--root", "--out" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "examples takes no items" };
        const out = p.value("--out") orelse return .{ .misuse = "examples: say where the files go, with --out DIR" };
        return .{ .examples = .{ .common = common, .out = out } };
    }
    if (eql(name, "pin")) {
        if (try p.allow(&.{ "--root", "--offline" })) |problem| return .{ .misuse = problem };
        if (words.len > 2) return .{ .misuse = "pin takes a repository, and a commit of it" };
        return .{ .pin = .{ .common = common, .name = if (words.len > 0) words[0] else null, .revision = if (words.len == 2) words[1] else null } };
    }
    if (eql(name, "trace")) {
        if (try p.allow(&.{ "--root", "--json", "--current", "--working", "--offline", "--results", "--implementation", "--implementation-version" })) |problem| return .{ .misuse = problem };
        if (words.len != 1) return .{ .misuse = "trace takes one item" };
        return .{ .trace = .{ .common = common, .id = words[0], .json = p.flag("--json"), .results = try p.results() } };
    }
    if (eql(name, "coverage")) {
        if (try p.allow(&.{ "--root", "--json", "--markdown", "--profile", "--current", "--working", "--offline", "--results", "--implementation", "--implementation-version", "--gitlab-requirements" })) |problem| return .{ .misuse = problem };
        if (p.flag("--json") and p.flag("--markdown")) return .{ .misuse = "give --json or --markdown, not both" };
        if (words.len > 0) return .{ .misuse = "coverage takes no items" };
        return .{ .coverage = .{ .common = common, .profile = p.value("--profile"), .json = p.flag("--json"), .markdown = p.flag("--markdown"), .results = try p.results(), .gitlab_requirements = p.value("--gitlab-requirements") } };
    }
    if (eql(name, "overlay")) {
        if (try p.allow(&.{ "--root", "--offline", "--remove" })) |problem| return .{ .misuse = problem };
        const remove = p.flag("--remove");
        if (words.len != 0 and words.len != (if (remove) @as(usize, 2) else 3)) return .{ .misuse = "overlay takes an issue, a field and a value (or, with --remove, an issue and a field), or nothing to list" };
        return .{ .overlay = .{
            .common = common,
            .issue = if (words.len > 0) words[0] else null,
            .field = if (words.len > 1) words[1] else null,
            .value = if (words.len > 2) words[2] else null,
            .remove = remove,
        } };
    }
    if (eql(name, "apply")) {
        if (try p.allow(&.{ "--root", "--offline", "--dry-run", "--force" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "apply takes no items" };
        return .{ .apply = .{ .common = common, .dry_run = p.flag("--dry-run"), .force = p.flag("--force") } };
    }
    if (eql(name, "mirror")) {
        if (try p.allow(&.{ "--root", "--offline" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "mirror takes no items" };
        return .{ .mirror = .{ .common = common } };
    }
    if (eql(name, "sync")) {
        if (try p.allow(&.{ "--root", "--offline", "--dry-run", "--force" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "sync takes no items" };
        return .{ .sync = .{ .common = common, .dry_run = p.flag("--dry-run"), .force = p.flag("--force") } };
    }
    if (eql(name, "publish")) {
        if (try p.allow(&.{ "--root", "--offline", "--to", "--url", "--dry-run" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "publish takes no items" };
        return .{ .publish = .{ .common = common, .to = p.value("--to"), .url = p.value("--url"), .dry_run = p.flag("--dry-run") } };
    }
    if (eql(name, "rewrite-refs")) {
        if (try p.allow(&.{ "--root", "--offline", "--dry-run" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "rewrite-refs takes no items" };
        return .{ .rewrite_refs = .{ .common = common, .dry_run = p.flag("--dry-run") } };
    }
    if (eql(name, "time")) {
        if (try p.allow(&.{ "--root", "--by", "--on", "--note", "--json", "--offline" })) |problem| return .{ .misuse = problem };
        if (words.len != 0 and words.len != 2) return .{ .misuse = "time takes a work item and the hours spent, or nothing for the report" };
        return .{ .time = .{ .common = common, .id = if (words.len == 2) words[0] else null, .hours = if (words.len == 2) words[1] else null, .by = p.value("--by"), .on = p.value("--on"), .note = p.value("--note"), .json = p.flag("--json") } };
    }
    if (eql(name, "gitlab-requirements")) {
        if (try p.allow(&.{ "--root", "--profile", "--dry-run" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "gitlab-requirements takes no items" };
        return .{ .gitlab_requirements = .{ .common = common, .profile = p.value("--profile"), .dry_run = p.flag("--dry-run") } };
    }
    if (eql(name, "jama")) {
        if (try p.allow(&.{ "--root", "--profile", "--dry-run" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "jama takes no items" };
        return .{ .jama = .{ .common = common, .profile = p.value("--profile"), .dry_run = p.flag("--dry-run") } };
    }
    if (eql(name, "level")) {
        if (try p.allow(&.{ "--root", "--write", "--offline" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "level takes no items" };
        return .{ .level = .{ .common = common, .write = p.flag("--write") } };
    }
    if (eql(name, "schedule")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "schedule takes no items" };
        return .{ .schedule = .{ .common = common } };
    }
    if (eql(name, "load")) {
        if (try p.allow(&.{ "--root", "--json" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "load takes no items" };
        return .{ .load = .{ .common = common, .json = p.flag("--json") } };
    }
    if (eql(name, "diff") or eql(name, "impact")) {
        const impact = eql(name, "impact");
        if (try p.allow(&.{ "--root", "--json", "--markdown" })) |problem| return .{ .misuse = problem };
        if (p.flag("--json") and p.flag("--markdown")) return .{ .misuse = "give --json or --markdown, not both" };
        if (impact and words.len > 1) return .{ .misuse = "impact takes one commit: it is about the project as it is now" };
        if (words.len > 2) return .{ .misuse = "diff takes one commit or two" };
        return .{ .diff = .{ .common = common, .revisions = words, .impact = impact, .json = p.flag("--json"), .markdown = p.flag("--markdown") } };
    }
    if (eql(name, "export")) {
        if (try p.allow(&.{ "--root", "--profile", "--current", "--working", "--offline" })) |problem| return .{ .misuse = problem };
        if (words.len > 1) return .{ .misuse = "export takes one thing to export" };
        const what = if (words.len == 0) .json else std.meta.stringToEnum(Export.What, words[0]) orelse
            return .{ .misuse = "export: json, items, links, citations, gitlab-requirements or reqif" };
        return .{ .exporting = .{ .common = common, .what = what, .profile = p.value("--profile") } };
    }
    if (eql(name, "baseline")) {
        if (try p.allow(&.{ "--root", "--message" })) |problem| return .{ .misuse = problem };
        if (words.len > 1) return .{ .misuse = "baseline takes one name" };
        if (words.len == 0 and p.value("--message") != null) return .{ .misuse = "baseline: a message goes with a name" };
        return .{ .baseline = .{ .common = common, .name = if (words.len == 1) words[0] else null, .message = p.value("--message") } };
    }
    if (eql(name, "link")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len != 3) return .{ .misuse = "link takes the item, the link type, and the item to link to" };
        return .{ .link = .{ .common = common, .from = words[0], .type_name = words[1], .to = words[2] } };
    }
    if (eql(name, "new")) {
        if (try p.allow(&.{ "--root", "--to" })) |problem| return .{ .misuse = problem };
        if (words.len == 0 or words.len > 2) return .{ .misuse = "new takes an item type, and the ID where the type's IDs are not numbered" };
        return .{ .new = .{ .common = common, .type_name = words[0], .id = if (words.len == 2) words[1] else null, .to = p.value("--to") } };
    }
    if (eql(name, "move")) {
        if (try p.allow(&.{ "--root", "--alias", "--no-alias" })) |problem| return .{ .misuse = problem };
        if (words.len != 2) return .{ .misuse = "move takes the ID an item has, and the ID it is to have" };
        if (p.flag("--alias") and p.flag("--no-alias")) return .{ .misuse = "give --alias or --no-alias, not both" };
        const keep: ?bool = if (p.flag("--alias")) true else if (p.flag("--no-alias")) false else null;
        return .{ .move = .{ .common = common, .old = words[0], .new = words[1], .alias = keep } };
    }
    if (eql(name, "render")) {
        if (try p.allow(&.{ "--root", "--out", "--format", "--profile", "--current", "--working", "--offline", "--results", "--implementation", "--implementation-version", "--editions", "--controlled", "--edit", "--wasm" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "render takes no items" };
        const format: Render.Format = if (p.value("--format")) |f| std.meta.stringToEnum(Render.Format, f) orelse
            return .{ .misuse = "render: the formats are markdown, html and document" } else .markdown;
        const out = p.value("--out") orelse return .{ .misuse = "render: say where the files go, with --out DIR" };
        if (p.flag("--edit") and (format != .html or p.value("--wasm") == null)) return .{ .misuse = "render --edit: with --format html, and --wasm FILE, skein built for WebAssembly (zig build wasm, or a release's skein-vVERSION-wasm32-wasi.wasm)" };
        if (p.value("--wasm") != null and !p.flag("--edit")) return .{ .misuse = "render --wasm: with --edit" };
        return .{ .render = .{ .common = common, .out = out, .format = format, .profile = p.value("--profile"), .results = try p.results(), .editions = p.flag("--editions"), .controlled = p.flag("--controlled"), .wasm = p.value("--wasm") } };
    }
    if (eql(name, "api")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len < 2 or words.len > 3) return .{ .misuse = "api takes GET or POST, a request's path (page, source, save) and its query" };
        const method: Api.Method = if (eql(words[0], "GET")) .get else if (eql(words[0], "POST")) .post else return .{ .misuse = "api: GET or POST" };
        return .{ .api = .{ .common = common, .method = method, .path = words[1], .query = if (words.len == 3) words[2] else "" } };
    }
    if (eql(name, "serve")) {
        if (try p.allow(&.{ "--root", "--port", "--profile", "--current", "--working", "--offline", "--results", "--implementation", "--implementation-version", "--listen", "--url", "--sign-in", "--user-header", "--email-header", "--proxy", "--issuer" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "serve takes no items" };
        const port = if (p.value("--port")) |n| std.fmt.parseInt(u16, n, 10) catch return .{ .misuse = "serve --port: a port's number, as 8080" } else Serve.default_port;
        const sign_in: Serve.SignIn = if (p.value("--sign-in")) |s| std.meta.stringToEnum(Serve.SignIn, s) orelse return .{ .misuse = "serve --sign-in: proxy, forge or oidc" } else .none;
        var o: Serve = .{ .common = common, .port = port, .profile = p.value("--profile"), .results = try p.results(), .url = p.value("--url"), .sign_in = sign_in, .proxies = try p.values("--proxy") };
        if (p.value("--listen")) |l| o.listen = l;
        if (p.value("--user-header")) |h| o.user_header = h;
        if (p.value("--email-header")) |h| o.email_header = h;
        _ = std.Io.net.IpAddress.parse(o.listen, port) catch return .{ .misuse = "serve --listen: an IP address, as 0.0.0.0 or 10.0.0.5" };
        if (!Serve.loopback(o.listen)) {
            if (sign_in == .none) return .{ .misuse = "serve --listen: on an address other than this computer's own, people sign in: give --sign-in proxy or forge" };
            if (o.url == null) return .{ .misuse = "serve --listen: give --url, the address people reach it at" };
        }
        if (sign_in == .forge and o.url == null) return .{ .misuse = "serve --sign-in forge: give --url, the address the forge sends people back to" };
        o.issuer = p.value("--issuer");
        if (sign_in == .oidc and (o.url == null or o.issuer == null)) return .{ .misuse = "serve --sign-in oidc: give --issuer, the OpenID Connect provider, and --url, the address it sends people back to" };
        return .{ .serve = o };
    }
    if (eql(name, "import")) {
        const forms = "import: doorstop DIR..., csv FILE, reqif FILE or jama PROJECT with --type TYPE --to DIR, or gitlab-requirements FILE";
        if (words.len == 0) return .{ .misuse = forms };
        const format = std.meta.stringToEnum(Import.Format, words[0]) orelse return .{ .misuse = forms };
        switch (format) {
            .doorstop => {
                if (try p.allow(&.{ "--root", "--headings-as-text", "--status-from", "--verification-from" })) |problem| return .{ .misuse = problem };
                if (words.len < 2) return .{ .misuse = "import doorstop: name the directories of the Doorstop documents" };
                return .{ .import = .{
                    .common = common,
                    .format = format,
                    .paths = words[1..],
                    .headings_as_text = p.flag("--headings-as-text"),
                    .status_from = p.value("--status-from"),
                    .verification_from = p.value("--verification-from"),
                } };
            },
            .csv => {
                if (try p.allow(&.{ "--root", "--type", "--to", "--id-column", "--text-column", "--replace" })) |problem| return .{ .misuse = problem };
                if (words.len != 2) return .{ .misuse = "import csv: name one CSV file" };
                return .{ .import = .{
                    .common = common,
                    .format = format,
                    .paths = words[1..],
                    .item_type = p.value("--type"),
                    .to = p.value("--to"),
                    .id_column = p.value("--id-column"),
                    .text_column = p.value("--text-column"),
                    .replace = p.flag("--replace"),
                } };
            },
            .reqif => {
                if (try p.allow(&.{ "--root", "--type", "--to", "--replace" })) |problem| return .{ .misuse = problem };
                if (words.len != 2) return .{ .misuse = "import reqif: name one ReqIF file" };
                return .{ .import = .{ .common = common, .format = format, .paths = words[1..], .item_type = p.value("--type"), .to = p.value("--to"), .replace = p.flag("--replace") } };
            },
            .jama => {
                if (try p.allow(&.{ "--root", "--type", "--to", "--replace", "--jama-type" })) |problem| return .{ .misuse = problem };
                if (words.len != 2) return .{ .misuse = "import jama: name the Jama project by its id" };
                return .{ .import = .{ .common = common, .format = format, .paths = words[1..], .item_type = p.value("--type"), .to = p.value("--to"), .replace = p.flag("--replace"), .jama_type = p.value("--jama-type") } };
            },
            .@"gitlab-requirements" => {
                if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
                if (words.len != 2) return .{ .misuse = "import gitlab-requirements: name the CSV file GitLab exported" };
                return .{ .import = .{ .common = common, .format = format, .paths = words[1..] } };
            },
        }
    }
    if (eql(name, "review") or eql(name, "clear")) {
        if (try p.allow(&.{ "--root", "--all" })) |problem| return .{ .misuse = problem };
        if (p.flag("--all") == (words.len > 0)) return .{ .misuse = "name the items, or give --all" };
        const review: Review = .{ .common = common, .ids = words, .all = p.flag("--all") };
        return if (eql(name, "review")) .{ .review = review } else .{ .clear = review };
    }
    if (eql(name, "result")) {
        if (try p.allow(&.{ "--root", "--by", "--on", "--note", "--implementation", "--evidence" })) |problem| return .{ .misuse = problem };
        if (words.len != 2) return .{ .misuse = "result takes the item and how it went: pass, fail or skip" };
        const outcome = std.meta.stringToEnum(Results.Outcome, words[1]) orelse return .{ .misuse = "result: pass, fail or skip" };
        return .{ .result = .{ .common = common, .id = words[0], .outcome = outcome, .by = p.value("--by"), .on = p.value("--on"), .note = p.value("--note"), .implementation = p.value("--implementation"), .evidence = try p.values("--evidence") } };
    }
    if (eql(name, "approve")) {
        if (try p.allow(&.{ "--root", "--by", "--on", "--from-pull-request", "--as", "--sign" })) |problem| return .{ .misuse = problem };
        if (p.value("--from-pull-request")) |n| {
            if (words.len > 0 or p.flag("--by") or p.flag("--on")) return .{ .misuse = "approve --from-pull-request takes the pull request's number alone" };
            const number = std.fmt.parseInt(u64, std.mem.trimStart(u8, n, "#"), 10) catch return .{ .misuse = "approve --from-pull-request: the number of a pull request" };
            return .{ .approve = .{ .common = common, .ids = &.{}, .from_pull_request = number } };
        }
        if (words.len == 0) return .{ .misuse = "name the items to approve" };
        return .{ .approve = .{ .common = common, .ids = words, .by = p.value("--by"), .on = p.value("--on"), .as = p.value("--as"), .sign = p.flag("--sign") } };
    }
    return .{ .unknown = name };
}

/// The arguments after the command's name, sorted out
const Parsed = struct {
    arena: std.mem.Allocator,
    command: []const u8,
    given: std.ArrayList(Given) = .empty,
    /// what is not an option
    words: std.ArrayList([]const u8) = .empty,

    const Given = struct { name: []const u8, value: []const u8 = "" };

    /// What is wrong with `args`, if anything
    fn read(self: *Parsed, args: []const []const u8) !?[]const u8 {
        var i: usize = 0;
        next: while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (!std.mem.startsWith(u8, arg, "--")) {
                try self.words.append(self.arena, arg);
                continue;
            }
            for (options) |option| {
                if (!eql(option.name, arg)) continue;
                if (!option.takes_value) {
                    try self.given.append(self.arena, .{ .name = option.name });
                    continue :next;
                }
                i += 1;
                if (i == args.len) return try self.arena.print("{s} needs a value after it", .{arg});
                try self.given.append(self.arena, .{ .name = option.name, .value = args[i] });
                continue :next;
            }
            return try self.arena.print("unknown option {s}", .{arg});
        }
        return null;
    }

    fn value(self: *const Parsed, name: []const u8) ?[]const u8 {
        for (self.given.items) |g| {
            if (eql(g.name, name)) return g.value;
        }
        return null;
    }

    fn flag(self: *const Parsed, name: []const u8) bool {
        return self.value(name) != null;
    }

    /// Every value of an option that may be given more than once
    fn values(self: *const Parsed, name: []const u8) ![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        for (self.given.items) |g| {
            if (eql(g.name, name)) try out.append(self.arena, g.value);
        }
        return out.items;
    }

    /// `--results`, and what produced those that name nothing
    fn results(self: *const Parsed) !Results.Given {
        return .{ .files = try self.values("--results"), .implementation = self.value("--implementation"), .version = self.value("--implementation-version") };
    }

    /// What is wrong when an option other than `allowed` was given
    fn allow(self: *const Parsed, allowed: []const []const u8) !?[]const u8 {
        next: for (self.given.items) |g| {
            for (allowed) |a| {
                if (eql(a, g.name)) continue :next;
            }
            return try self.arena.print("{s} does not go with {s}", .{ g.name, self.command });
        }
        return null;
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test {
    _ = @import("_test/cli.zig");
}
