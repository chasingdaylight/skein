//! The command line: which command the arguments ask for.

const std = @import("std");

pub const usage =
    \\Usage: skein <command> [options]
    \\
    \\Commands:
    \\  check             Check the project: its configuration, schema and items
    \\  trace ID          Show an item with what is above and below it
    \\  coverage          Count the items that are linked to or cited as expected
    \\  review ID...      Record the links of these items as reviewed
    \\  clear ID...       Record the links to these items as reviewed
    \\  approve ID...     Record an approval of these items as they are now
    \\  help              Show this text
    \\  version           Show skein's version
    \\
    \\Options:
    \\  --root DIR        The project, or a directory inside it (default: here)
    \\  --json            trace, coverage: as JSON
    \\  --profile NAME    coverage: only the items of this profile
    \\  --all             review, clear: every link, not those of the items named
    \\  --by NAME         approve: who approves (default: git's user.name)
    \\  --on DATE         approve: when, as 2027-03-01 (default: today)
    \\
;

pub const Command = union(enum) {
    help,
    version,
    check: Common,
    trace: Trace,
    coverage: Coverage,
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
    .{ .name = "--profile", .takes_value = true },
    .{ .name = "--all", .takes_value = false },
    .{ .name = "--by", .takes_value = true },
    .{ .name = "--on", .takes_value = true },
};

/// The command `args` (without the program's name) ask for; help when
/// there are none. What it returns is allocated in `arena` or points
/// into `args`.
pub fn parse(arena: std.mem.Allocator, args: []const []const u8) std.mem.Allocator.Error!Command {
    if (args.len == 0) return .help;
    const name = args[0];
    if (eql(name, "help") or eql(name, "--help") or eql(name, "-h")) return .help;
    if (eql(name, "version") or eql(name, "--version")) return .version;

    var p: Parsed = .{ .arena = arena, .command = name };
    if (try p.read(args[1..])) |problem| return .{ .misuse = problem };
    const common: Common = .{ .root = p.value("--root") orelse "." };
    const words = p.words.items;

    if (eql(name, "check")) {
        if (try p.allow(&.{"--root"})) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "check takes no items" };
        return .{ .check = common };
    }
    if (eql(name, "trace")) {
        if (try p.allow(&.{ "--root", "--json" })) |problem| return .{ .misuse = problem };
        if (words.len != 1) return .{ .misuse = "trace takes one item" };
        return .{ .trace = .{ .common = common, .id = words[0], .json = p.flag("--json") } };
    }
    if (eql(name, "coverage")) {
        if (try p.allow(&.{ "--root", "--json", "--profile" })) |problem| return .{ .misuse = problem };
        if (words.len > 0) return .{ .misuse = "coverage takes no items" };
        return .{ .coverage = .{ .common = common, .profile = p.value("--profile"), .json = p.flag("--json") } };
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
