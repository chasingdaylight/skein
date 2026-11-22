//! The command line: which command the arguments ask for.

const std = @import("std");

const Network = @import("network/Network.zig");

pub const usage =
    \\Usage: skein <command> [options]
    \\
    \\Commands:
    \\  check             Check the project: its configuration, schema and items
    \\  trace ID          Show an item with what is above and below it
    \\  coverage          Count the items that are linked to or cited as expected
    \\  diff [REV [REV]]  Show the items added, removed or changed since a commit
    \\  impact [REV]      Show what the changes since a commit reach
    \\  export [WHAT]     Write the graph as JSON, or items, links or citations as CSV
    \\  render --out DIR  Write the documents as Markdown for a site generator
    \\  move OLD NEW      Give an item another ID, everywhere the old one is used
    \\  new TYPE [ID]     Start an item: its file, or the marker for a document
    \\  link FROM TYPE TO Add a link of a type from one item to another
    \\  baseline [NAME]   Tag what is committed as a baseline; without NAME, list them
    \\  pin [NAME [REV]]  Record the commits of the other repositories that the items
    \\                    are checked against (default: what each has checked out)
    \\  import doorstop DIR...
    \\                    Turn Doorstop documents into skein items, in place
    \\  import csv FILE --type TYPE --to DIR
    \\                    Make an item file in DIR of each row of a CSV file
    \\  review ID...      Record the links of these items as reviewed
    \\  clear ID...       Record the links to these items as reviewed
    \\  approve ID...     Record an approval of these items as they are now
    \\  lsp               Serve editors as a language server, on standard input and output
    \\  help              Show this text
    \\  version           Show skein's version
    \\
    \\Options:
    \\  --root DIR        The project, or a directory inside it (default: here)
    \\  --json            trace, coverage, diff, impact: as JSON
    \\  --markdown        coverage, diff, impact: as Markdown, for a pull request
    \\  --profile NAME    coverage, export, render: only the items of this profile
    \\  --current         check, trace, coverage, export, render: read the other
    \\                    repositories at the commit each has checked out, not the
    \\                    one pinned
    \\  --working         the same, with their files as they are, committed or not
    \\  --all            review, clear: every link, not those of the items named
    \\  --by NAME         approve: who approves (default: git's user.name)
    \\  --on DATE         approve: when, as 2027-03-01 (default: today)
    \\  --type TYPE       import csv: the item type of the rows
    \\  --to DIR          import csv: where the item files go
    \\  --id-column NAME, --text-column NAME
    \\                    import csv: the columns of the IDs and the text
    \\                    (default: id, text)
    \\  --replace         import csv: write over item files that are there
    \\  --headings-as-text
    \\                    import doorstop: non-normative items as plain Markdown
    \\  --status-from NAME, --verification-from NAME
    \\                    import doorstop: the attribute that gives the status,
    \\                    or the verification method
    \\  --out DIR         render: where the rendered files go
    \\  --format NAME     render: markdown for a site generator (the default),
    \\                    html: the site itself, or document: one file per document
    \\
;

pub const Command = union(enum) {
    help,
    version,
    check: Common,
    trace: Trace,
    coverage: Coverage,
    /// `diff`, and `impact`
    diff: Diff,
    /// `export`
    exporting: Export,
    render: Render,
    move: Move,
    new: New,
    link: Link,
    baseline: Baseline,
    pin: Pin,
    /// the language server
    lsp,
    import: Import,
    review: Review,
    clear: Review,
    approve: Approve,
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
};

pub const Coverage = struct {
    common: Common = .{},
    profile: ?[]const u8 = null,
    json: bool = false,
    /// as Markdown, for a job summary or a pull request
    markdown: bool = false,
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
};

pub const Render = struct {
    common: Common = .{},
    /// the directory the rendered files go to, from where skein is run
    out: []const u8,
    format: Format = .markdown,
    /// only the items of this profile
    profile: ?[]const u8 = null,

    pub const Format = enum {
        /// Markdown for a site generator
        markdown,
        /// the site itself: HTML pages
        html,
        /// each document as one HTML file of its own, for delivery
        document,
    };
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

    pub const Format = enum { doorstop, csv };
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
    };
    const words = p.words.items;

    if (eql(name, "check")) {
        if (try p.allow(&.{ "--root", "--current", "--working" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "check takes no items" };
        return .{ .check = common };
    }
    if (eql(name, "pin")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len > 2) return .{ .misuse = "pin takes a repository, and a commit of it" };
        return .{ .pin = .{ .common = common, .name = if (words.len > 0) words[0] else null, .revision = if (words.len == 2) words[1] else null } };
    }
    if (eql(name, "trace")) {
        if (try p.allow(&.{ "--root", "--json", "--current", "--working" })) |problem| return .{ .misuse = problem };
        if (words.len != 1) return .{ .misuse = "trace takes one item" };
        return .{ .trace = .{ .common = common, .id = words[0], .json = p.flag("--json") } };
    }
    if (eql(name, "coverage")) {
        if (try p.allow(&.{ "--root", "--json", "--markdown", "--profile", "--current", "--working" })) |problem| return .{ .misuse = problem };
        if (p.flag("--json") and p.flag("--markdown")) return .{ .misuse = "give --json or --markdown, not both" };
        if (words.len > 0) return .{ .misuse = "coverage takes no items" };
        return .{ .coverage = .{ .common = common, .profile = p.value("--profile"), .json = p.flag("--json"), .markdown = p.flag("--markdown") } };
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
        if (try p.allow(&.{ "--root", "--profile", "--current", "--working" })) |problem| return .{ .misuse = problem };
        if (words.len > 1) return .{ .misuse = "export takes one thing to export" };
        const what = if (words.len == 0) .json else std.meta.stringToEnum(Export.What, words[0]) orelse
            return .{ .misuse = "export: json, items, links or citations" };
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
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len != 2) return .{ .misuse = "move takes the ID an item has, and the ID it is to have" };
        return .{ .move = .{ .common = common, .old = words[0], .new = words[1] } };
    }
    if (eql(name, "render")) {
        if (try p.allow(&.{ "--root", "--out", "--format", "--profile", "--current", "--working" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "render takes no items" };
        const format: Render.Format = if (p.value("--format")) |f| std.meta.stringToEnum(Render.Format, f) orelse
            return .{ .misuse = "render: the formats are markdown, html and document" } else .markdown;
        const out = p.value("--out") orelse return .{ .misuse = "render: say where the files go, with --out DIR" };
        return .{ .render = .{ .common = common, .out = out, .format = format, .profile = p.value("--profile") } };
    }
    if (eql(name, "import")) {
        const forms = "import: doorstop DIR..., or csv FILE --type TYPE --to DIR";
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
        }
    }
    if (eql(name, "review") or eql(name, "clear")) {
        if (try p.allow(&.{ "--root", "--all" })) |problem| return .{ .misuse = problem };
        if (p.flag("--all") == (words.len > 0)) return .{ .misuse = "name the items, or give --all" };
        const review: Review = .{ .common = common, .ids = words, .all = p.flag("--all") };
        return if (eql(name, "review")) .{ .review = review } else .{ .clear = review };
    }
    if (eql(name, "approve")) {
        if (try p.allow(&.{ "--root", "--by", "--on" })) |problem| return .{ .misuse = problem };
        if (words.len == 0) return .{ .misuse = "name the items to approve" };
        return .{ .approve = .{ .common = common, .ids = words, .by = p.value("--by"), .on = p.value("--on") } };
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

// req: cli.commands, cli.options, principle.no-silent-mistakes
const testing = std.testing;

/// A parser for tests, whose arena is freed with `deinit`
const Fixture = struct {
    arena: std.heap.ArenaAllocator,

    fn init() Fixture {
        return .{ .arena = .init(testing.allocator) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }

    fn run(self: *Fixture, args: []const []const u8) !Command {
        return parse(self.arena.allocator(), args);
    }
};

test "no arguments ask for help" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(Command.help, try f.run(&.{}));
}

test "help and version, as commands and as options" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(Command.help, try f.run(&.{"help"}));
    try testing.expectEqual(Command.help, try f.run(&.{"--help"}));
    try testing.expectEqual(Command.help, try f.run(&.{"-h"}));
    try testing.expectEqual(Command.version, try f.run(&.{"version"}));
    try testing.expectEqual(Command.version, try f.run(&.{"--version"}));
}

test "an unknown command is reported by name" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqualStrings("frobnicate", (try f.run(&.{ "frobnicate", "x" })).unknown);
}

test "options: values, unknown ones, and ones that do not go with the command" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqualStrings(".", (try f.run(&.{"check"})).check.root);
    try testing.expectEqualStrings("docs", (try f.run(&.{ "check", "--root", "docs" })).check.root);
    try testing.expectEqualStrings("--root needs a value after it", (try f.run(&.{ "check", "--root" })).misuse);
    try testing.expectEqualStrings("check takes no items", (try f.run(&.{ "check", "everything" })).misuse);
    try testing.expectEqualStrings("unknown option --fast", (try f.run(&.{ "check", "--fast" })).misuse);
    try testing.expectEqualStrings("--json does not go with check", (try f.run(&.{ "check", "--json" })).misuse);
    try testing.expectEqualStrings("--profile does not go with trace", (try f.run(&.{ "trace", "a.b", "--profile", "s0" })).misuse);
}

test "trace takes one item" {
    var f: Fixture = .init();
    defer f.deinit();
    const t = (try f.run(&.{ "trace", "--json", "a.b" })).trace;
    try testing.expectEqualStrings("a.b", t.id);
    try testing.expect(t.json);
    try testing.expectEqualStrings("trace takes one item", (try f.run(&.{"trace"})).misuse);
    try testing.expectEqualStrings("trace takes one item", (try f.run(&.{ "trace", "a", "b" })).misuse);
}

test "coverage takes a profile" {
    var f: Fixture = .init();
    defer f.deinit();
    const c = (try f.run(&.{ "coverage", "--profile", "s0", "--json" })).coverage;
    try testing.expectEqualStrings("s0", c.profile.?);
    try testing.expect(c.json);
    try testing.expectEqual(null, (try f.run(&.{"coverage"})).coverage.profile);
    try testing.expectEqualStrings("--profile needs a value after it", (try f.run(&.{ "coverage", "--profile" })).misuse);
}

test "review and clear take items, or all" {
    var f: Fixture = .init();
    defer f.deinit();
    const review = (try f.run(&.{ "review", "a.b", "--root", "docs", "c.d" })).review;
    try testing.expectEqual(2, review.ids.len);
    try testing.expectEqualStrings("c.d", review.ids[1]);
    try testing.expectEqualStrings("docs", review.common.root);
    try testing.expect(!review.all);
    try testing.expect((try f.run(&.{ "clear", "--all" })).clear.all);
    try testing.expectEqualStrings("name the items, or give --all", (try f.run(&.{"review"})).misuse);
    try testing.expectEqualStrings("name the items, or give --all", (try f.run(&.{ "clear", "a.b", "--all" })).misuse);
}

test "approve takes items, and who and when" {
    var f: Fixture = .init();
    defer f.deinit();
    const approve = (try f.run(&.{ "approve", "SRS-001", "--by", "A. Reviewer", "--on", "2027-03-01", "SRS-002" })).approve;
    try testing.expectEqual(2, approve.ids.len);
    try testing.expectEqualStrings("A. Reviewer", approve.by.?);
    try testing.expectEqualStrings("2027-03-01", approve.on.?);
    try testing.expectEqual(null, (try f.run(&.{ "approve", "a.b" })).approve.by);
    try testing.expectEqualStrings("name the items to approve", (try f.run(&.{"approve"})).misuse);
}

test "diff and impact take commits" {
    var f: Fixture = .init();
    defer f.deinit();
    const d = (try f.run(&.{ "diff", "v0.1", "HEAD", "--json" })).diff;
    try testing.expectEqual(2, d.revisions.len);
    try testing.expectEqualStrings("HEAD", d.revisions[1]);
    try testing.expect(d.json and !d.impact and !d.markdown);
    const i = (try f.run(&.{ "impact", "--markdown" })).diff;
    try testing.expect(i.impact and i.markdown);
    try testing.expectEqual(0, i.revisions.len);
    try testing.expectEqualStrings("diff takes one commit or two", (try f.run(&.{ "diff", "a", "b", "c" })).misuse);
    try testing.expectEqualStrings("impact takes one commit: it is about the project as it is now", (try f.run(&.{ "impact", "a", "b" })).misuse);
    try testing.expectEqualStrings("give --json or --markdown, not both", (try f.run(&.{ "diff", "--json", "--markdown" })).misuse);
}

test "export takes what to export" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(.json, (try f.run(&.{"export"})).exporting.what);
    const e = (try f.run(&.{ "export", "links", "--profile", "s0" })).exporting;
    try testing.expectEqual(.links, e.what);
    try testing.expectEqualStrings("s0", e.profile.?);
    try testing.expectEqualStrings("export: json, items, links or citations", (try f.run(&.{ "export", "everything" })).misuse);
}

test "lsp takes nothing but the transport" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(.lsp, try f.run(&.{"lsp"}));
    try testing.expectEqual(.lsp, try f.run(&.{ "lsp", "--stdio" }));
    try testing.expectEqualStrings("lsp takes no arguments", (try f.run(&.{ "lsp", "--port", "1" })).misuse);
}

test "link takes two items and a type" {
    var f: Fixture = .init();
    defer f.deinit();
    const l = (try f.run(&.{ "link", "c.one", "verifies", "lex.a" })).link;
    try testing.expectEqualStrings("c.one", l.from);
    try testing.expectEqualStrings("verifies", l.type_name);
    try testing.expectEqualStrings("lex.a", l.to);
    try testing.expectEqualStrings("link takes the item, the link type, and the item to link to", (try f.run(&.{ "link", "c.one" })).misuse);
}

test "new takes a type, and maybe an ID" {
    var f: Fixture = .init();
    defer f.deinit();
    const n = (try f.run(&.{ "new", "srs", "--to", "requirements" })).new;
    try testing.expectEqualStrings("srs", n.type_name);
    try testing.expectEqual(null, n.id);
    try testing.expectEqualStrings("requirements", n.to.?);
    try testing.expectEqualStrings("lex.a", (try f.run(&.{ "new", "rule", "lex.a" })).new.id.?);
    try testing.expectEqualStrings("new takes an item type, and the ID where the type's IDs are not numbered", (try f.run(&.{"new"})).misuse);
}

test "move takes two IDs" {
    var f: Fixture = .init();
    defer f.deinit();
    const m = (try f.run(&.{ "move", "lex.a", "lex.b" })).move;
    try testing.expectEqualStrings("lex.a", m.old);
    try testing.expectEqualStrings("lex.b", m.new);
    try testing.expectEqualStrings("move takes the ID an item has, and the ID it is to have", (try f.run(&.{ "move", "lex.a" })).misuse);
}

test "render needs a place to write to" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqualStrings("site", (try f.run(&.{ "render", "--out", "site", "--format", "markdown" })).render.out);
    try testing.expectEqualStrings("render: say where the files go, with --out DIR", (try f.run(&.{"render"})).misuse);
    try testing.expectEqual(.html, (try f.run(&.{ "render", "--out", "x", "--format", "html" })).render.format);
    try testing.expectEqualStrings("render: the formats are markdown, html and document", (try f.run(&.{ "render", "--out", "x", "--format", "pdf" })).misuse);
}

test "import takes a format and what to import" {
    var f: Fixture = .init();
    defer f.deinit();
    const i = (try f.run(&.{ "import", "doorstop", "docs/sys", "docs/srs" })).import;
    try testing.expectEqual(.doorstop, i.format);
    try testing.expectEqual(2, i.paths.len);
    try testing.expectEqualStrings("docs/srs", i.paths[1]);
    try testing.expect(std.mem.startsWith(u8, (try f.run(&.{"import"})).misuse, "import: doorstop DIR..."));
    try testing.expect(std.mem.startsWith(u8, (try f.run(&.{ "import", "excel", "x" })).misuse, "import: doorstop DIR..."));
    try testing.expectEqualStrings("import doorstop: name the directories of the Doorstop documents", (try f.run(&.{ "import", "doorstop" })).misuse);
}

test "pin, and the state of the other repositories" {
    var f: Fixture = .init();
    defer f.deinit();
    const all = (try f.run(&.{"pin"})).pin;
    try testing.expectEqual(null, all.name);
    const one = (try f.run(&.{ "pin", "compiler", "v1.2" })).pin;
    try testing.expectEqualStrings("compiler", one.name.?);
    try testing.expectEqualStrings("v1.2", one.revision.?);
    try testing.expectEqualStrings("pin takes a repository, and a commit of it", (try f.run(&.{ "pin", "a", "b", "c" })).misuse);
    try testing.expectEqual(.recorded, (try f.run(&.{"check"})).check.state);
    try testing.expectEqual(.current, (try f.run(&.{ "check", "--current" })).check.state);
    try testing.expectEqual(.working, (try f.run(&.{ "trace", "x", "--working" })).trace.common.state);
    try testing.expectEqualStrings("give --current or --working, not both", (try f.run(&.{ "check", "--current", "--working" })).misuse);
    try testing.expectEqualStrings("--current does not go with pin", (try f.run(&.{ "pin", "--current" })).misuse);
}
