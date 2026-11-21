//! The command line: which command the arguments ask for.

const std = @import("std");

pub const usage =
    \\Usage: skein <command> [options]
    \\
    \\Commands:
    \\  check             Check the project: its configuration, schema and items
    \\  review ID...      Record the links of these items as reviewed
    \\  clear ID...       Record the links to these items as reviewed
    \\  trace ID          Show an item with what is above and below it
    \\  coverage          Count the items that are linked to or cited as expected
    \\  help              Show this text
    \\  version           Show skein's version
    \\
    \\Options:
    \\  --root DIR        The project, or a directory inside it (default: here)
    \\  --all             review, clear: every link, not those of the items named
    \\  --profile NAME    coverage: only the items of this profile
    \\  --json            trace, coverage: as JSON
    \\
;

pub const Command = union(enum) {
    help,
    version,
    check: Common,
    review: Review,
    trace: Trace,
    coverage: Coverage,
    clear: Review,
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

/// The command `args` (without the program's name) ask for; help when
/// there are none. Lists it returns are allocated in `arena`.
pub fn parse(arena: std.mem.Allocator, args: []const []const u8) std.mem.Allocator.Error!Command {
    if (args.len == 0) return .help;
    const name = args[0];
    if (eql(name, "help") or eql(name, "--help") or eql(name, "-h")) return .help;
    if (eql(name, "version") or eql(name, "--version")) return .version;

    var p: Parsed = .{};
    if (try p.read(arena, args[1..])) |problem| return .{ .misuse = problem };
    if (eql(name, "trace")) {
        if (p.words.items.len != 1 or p.all) return .{ .misuse = "trace takes one item" };
        return .{ .trace = .{ .common = p.common, .id = p.words.items[0], .json = p.json } };
    }
    if (eql(name, "coverage")) {
        if (p.words.items.len > 0 or p.all) return .{ .misuse = "coverage takes no arguments but its options" };
        return .{ .coverage = .{ .common = p.common, .profile = p.profile, .json = p.json } };
    }
    if (p.json) return .{ .misuse = "--json goes with trace and coverage" };
    if (p.profile != null) return .{ .misuse = "--profile goes with coverage" };
    if (eql(name, "check")) {
        if (p.words.items.len > 0 or p.all) return .{ .misuse = "check takes no arguments but --root" };
        return .{ .check = p.common };
    }
    if (eql(name, "review") or eql(name, "clear")) {
        if (p.all == (p.words.items.len > 0)) return .{ .misuse = "name the items, or give --all" };
        const review: Review = .{ .common = p.common, .ids = p.words.items, .all = p.all };
        return if (eql(name, "review")) .{ .review = review } else .{ .clear = review };
    }
    return .{ .unknown = name };
}

/// The arguments after the command's name, sorted out
const Parsed = struct {
    common: Common = .{},
    all: bool = false,
    json: bool = false,
    profile: ?[]const u8 = null,
    /// what is not an option
    words: std.ArrayList([]const u8) = .empty,

    /// What is wrong with `args`, if anything
    fn read(self: *Parsed, arena: std.mem.Allocator, args: []const []const u8) !?[]const u8 {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (eql(arg, "--root")) {
                i += 1;
                if (i == args.len) return "--root needs a directory";
                self.common.root = args[i];
            } else if (eql(arg, "--profile")) {
                i += 1;
                if (i == args.len) return "--profile needs a name";
                self.profile = args[i];
            } else if (eql(arg, "--json")) {
                self.json = true;
            } else if (eql(arg, "--all")) {
                self.all = true;
            } else if (std.mem.startsWith(u8, arg, "--")) {
                return "unknown option";
            } else try self.words.append(arena, arg);
        }
        return null;
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const testing = std.testing;

fn parseTest(arena: *std.heap.ArenaAllocator, args: []const []const u8) !Command {
    return parse(arena.allocator(), args);
}

test "no arguments ask for help" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(Command.help, try parseTest(&arena, &.{}));
}

test "help and version, as commands and as options" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(Command.help, try parseTest(&arena, &.{"help"}));
    try testing.expectEqual(Command.help, try parseTest(&arena, &.{"--help"}));
    try testing.expectEqual(Command.help, try parseTest(&arena, &.{"-h"}));
    try testing.expectEqual(Command.version, try parseTest(&arena, &.{"version"}));
    try testing.expectEqual(Command.version, try parseTest(&arena, &.{"--version"}));
}

test "an unknown command is reported by name" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("frobnicate", (try parseTest(&arena, &.{ "frobnicate", "x" })).unknown);
}

test "check takes the project's place" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(".", (try parseTest(&arena, &.{"check"})).check.root);
    try testing.expectEqualStrings("docs", (try parseTest(&arena, &.{ "check", "--root", "docs" })).check.root);
    try testing.expectEqualStrings("--root needs a directory", (try parseTest(&arena, &.{ "check", "--root" })).misuse);
    try testing.expectEqualStrings("check takes no arguments but --root", (try parseTest(&arena, &.{ "check", "everything" })).misuse);
    try testing.expectEqualStrings("unknown option", (try parseTest(&arena, &.{ "check", "--fast" })).misuse);
}

test "review and clear take items, or all" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const review = (try parseTest(&arena, &.{ "review", "a.b", "--root", "docs", "c.d" })).review;
    try testing.expectEqual(2, review.ids.len);
    try testing.expectEqualStrings("c.d", review.ids[1]);
    try testing.expectEqualStrings("docs", review.common.root);
    try testing.expect(!review.all);
    try testing.expect((try parseTest(&arena, &.{ "clear", "--all" })).clear.all);
    try testing.expectEqualStrings("name the items, or give --all", (try parseTest(&arena, &.{"review"})).misuse);
    try testing.expectEqualStrings("name the items, or give --all", (try parseTest(&arena, &.{ "clear", "a.b", "--all" })).misuse);
}
