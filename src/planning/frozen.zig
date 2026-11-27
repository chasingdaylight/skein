//! The forge's values a plan uses, frozen at a baseline (#298; design,
//! section 6): what the forge said of each work item's issue (its
//! assignees, its milestone and the day it is due, whether it is open),
//! written by `skein baseline NAME` to `.skein/baselines/NAME.toml`,
//! committed, and tagged with the rest. A baseline's plan is then read from
//! that file (an edition of it, `render --editions`), not from the forge as
//! it is now.
//!
//!     # The forge's values the plan used at the baseline v1.0: written by skein baseline.
//!     offline = false
//!
//!     ["example/spec#12"]
//!     open = true
//!     assignees = ["ada"]
//!     milestone = "v1"
//!     due = "2027-03-01"

const std = @import("std");
const Io = std.Io;

const github = @import("../forge/github.zig");
const toml = @import("../toml.zig");
const write_toml = @import("../toml/write.zig");

pub const dir = ".skein/baselines";

pub const Entry = struct { key: []const u8, issue: github.Issue };

/// The file of the baseline `name`
pub fn fileOf(arena: std.mem.Allocator, name: []const u8) ![]const u8 {
    return arena.print("{s}/{s}.toml", .{ dir, name });
}

/// The text of the file: each issue by its key (`owner/repo#N`), in order
pub fn text(arena: std.mem.Allocator, name: []const u8, offline: bool, entries: []const Entry) ![]const u8 {
    const sorted = try arena.dupe(Entry, entries);
    std.mem.sort(Entry, sorted, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lt);
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "# The forge's values the plan used at the baseline {s}: written by skein baseline.\n", .{name});
    try out.print(arena, "offline = {}\n", .{offline});
    for (sorted) |e| {
        try out.print(arena, "\n[{s}]\nopen = {}\n", .{ try write_toml.string(arena, e.key), e.issue.open });
        if (e.issue.assignees.len > 0) {
            try out.appendSlice(arena, "assignees = [");
            for (e.issue.assignees, 0..) |login, i| try out.print(arena, "{s}{s}", .{ if (i > 0) ", " else "", try write_toml.string(arena, login) });
            try out.appendSlice(arena, "]\n");
        }
        if (e.issue.milestone) |m| try out.print(arena, "milestone = {s}\n", .{try write_toml.string(arena, m)});
        if (e.issue.due) |d| try out.print(arena, "due = {s}\n", .{try write_toml.string(arena, d)});
    }
    return out.items;
}

/// What the file of the baseline `name` under `root` says, by key; null
/// when there is none (the baseline froze nothing, or was made before)
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, name: []const u8) !?std.array_hash_map.String(github.Issue) {
    const source = root.readFileAlloc(io, try fileOf(arena, name), arena, .limited(1 << 24)) catch return null;
    return try parse(arena, source);
}

pub fn parse(arena: std.mem.Allocator, source: []const u8) !?std.array_hash_map.String(github.Issue) {
    var diag: toml.Diagnostic = .{};
    const t = toml.parse(arena, source, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return null,
    };
    var out: std.array_hash_map.String(github.Issue) = .empty;
    for (t.keys()) |key| {
        const v = t.get(key).?;
        if (v != .table) continue;
        const it = v.table;
        var issue: github.Issue = .{ .title = "", .open = true, .pull = false };
        if (it.get("open")) |o| if (o == .boolean) {
            issue.open = o.boolean;
        };
        if (it.get("assignees")) |list| if (list == .array) {
            var logins: std.ArrayList([]const u8) = .empty;
            for (list.array.items.items) |l| if (l == .string) try logins.append(arena, l.string);
            issue.assignees = logins.items;
        };
        if (it.get("milestone")) |m| if (m == .string) {
            issue.milestone = m.string;
        };
        if (it.get("due")) |d| if (d == .string) {
            issue.due = d.string;
        };
        try out.put(arena, key, issue);
    }
    return out;
}

test "a baseline's forge values, written and read back" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const written = try text(a, "v1.0", false, &.{
        .{ .key = "example/spec#7", .issue = .{ .title = "", .open = false, .pull = false } },
        .{ .key = "example/spec#12", .issue = .{ .title = "", .open = true, .pull = false, .assignees = &.{ "ada", "bob" }, .milestone = "v1", .due = "2027-03-01" } },
    });
    try std.testing.expectEqualStrings(
        \\# The forge's values the plan used at the baseline v1.0: written by skein baseline.
        \\offline = false
        \\
        \\["example/spec#12"]
        \\open = true
        \\assignees = ["ada", "bob"]
        \\milestone = "v1"
        \\due = "2027-03-01"
        \\
        \\["example/spec#7"]
        \\open = false
        \\
    , written);
    const back = (try parse(a, written)).?;
    try std.testing.expectEqualStrings("bob", back.get("example/spec#12").?.assignees[1]);
    try std.testing.expectEqualStrings("2027-03-01", back.get("example/spec#12").?.due.?);
    try std.testing.expect(!back.get("example/spec#7").?.open);
}
