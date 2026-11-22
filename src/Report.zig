//! The problems a command found, each with the file (and place) it is in,
//! and the warnings: what could not be checked, which fails nothing.

const std = @import("std");

const Report = @This();

arena: std.mem.Allocator,
problems: std.ArrayList(Problem) = .empty,
warnings: std.ArrayList(Problem) = .empty,

pub const Problem = struct {
    /// path from the project's root, with forward slashes
    file: []const u8,
    /// 0 when the problem is not at one line
    line: u32 = 0,
    column: u32 = 0,
    message: []const u8,
    /// what would mend it, which an editor offers as a quick fix
    fix: ?Fix = null,
};

/// A word to write in place of another, on the problem's line or the
/// lines of its item after it
pub const Fix = struct { old: []const u8, new: []const u8 };

/// Gives the problem or warning recorded last a fix
pub fn fixLast(self: *Report, of: enum { problem, warning }, fix: Fix) void {
    const list = switch (of) {
        .problem => self.problems.items,
        .warning => self.warnings.items,
    };
    list[list.len - 1].fix = fix;
}

pub fn add(
    self: *Report,
    file: []const u8,
    line: u32,
    column: u32,
    comptime fmt: []const u8,
    args: anytype,
) std.mem.Allocator.Error!void {
    try self.problems.append(self.arena, try make(self.arena, file, line, column, fmt, args));
}

/// Records a warning: something that was not checked, not a problem
pub fn warn(
    self: *Report,
    file: []const u8,
    line: u32,
    column: u32,
    comptime fmt: []const u8,
    args: anytype,
) std.mem.Allocator.Error!void {
    try self.warnings.append(self.arena, try make(self.arena, file, line, column, fmt, args));
}

fn make(arena: std.mem.Allocator, file: []const u8, line: u32, column: u32, comptime fmt: []const u8, args: anytype) std.mem.Allocator.Error!Problem {
    return .{ .file = try arena.dupe(u8, file), .line = line, .column = column, .message = try arena.print(fmt, args) };
}

/// Whether there are no problems; warnings do not count
pub fn ok(self: *const Report) bool {
    return self.problems.items.len == 0;
}

/// The problems and warnings as text, one per line (`file:line:column:
/// error: message`, or `warning:`), ordered by file and place.
pub fn render(self: *Report, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (try self.sorted(arena)) |l| {
        try out.appendSlice(arena, l.p.file);
        if (l.p.line > 0) try out.print(arena, ":{d}:{d}", .{ l.p.line, l.p.column });
        try out.print(arena, ": {s}: {s}\n", .{ l.kind, l.p.message });
    }
    return out.items;
}

/// The problems and warnings as GitHub Actions workflow commands, which
/// show each on its line of a pull request:
/// `::error file=F,line=L,col=C::message`
pub fn renderGithub(self: *Report, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (try self.sorted(arena)) |l| {
        try out.print(arena, "::{s} file={s}", .{ l.kind, try escapeGithub(arena, l.p.file, true) });
        if (l.p.line > 0) try out.print(arena, ",line={d},col={d}", .{ l.p.line, @max(l.p.column, 1) });
        try out.print(arena, ",title=skein::{s}\n", .{try escapeGithub(arena, l.p.message, false)});
    }
    return out.items;
}

/// A value of a workflow command: `%`, line ends, and in a property `:`
/// and `,`, written as GitHub reads them
fn escapeGithub(arena: std.mem.Allocator, s: []const u8, property: bool) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| switch (c) {
        '%' => try out.appendSlice(arena, "%25"),
        '\r' => try out.appendSlice(arena, "%0D"),
        '\n' => try out.appendSlice(arena, "%0A"),
        ':' => if (property) try out.appendSlice(arena, "%3A") else try out.append(arena, c),
        ',' => if (property) try out.appendSlice(arena, "%2C") else try out.append(arena, c),
        else => try out.append(arena, c),
    };
    return out.items;
}

/// The problems and warnings as JSON, for agents:
/// `{"ok": B, "problems": [{"file", "line", "column", "severity", "message"}]}`
pub fn renderJson(self: *Report, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    const Json = @import("output/Json.zig");
    var j: Json = .{ .arena = arena };
    try j.beginObject();
    try j.key("ok");
    try j.boolean(self.ok());
    try j.key("problems");
    try j.beginArray();
    for (try self.sorted(arena)) |l| {
        try j.beginObject();
        try j.key("file");
        try j.string(l.p.file);
        try j.key("line");
        try j.integer(l.p.line);
        try j.key("column");
        try j.integer(l.p.column);
        try j.key("severity");
        try j.string(l.kind);
        try j.key("message");
        try j.string(l.p.message);
        if (l.p.fix) |f| {
            try j.key("fix");
            try j.string(try arena.print("write '{s}' for '{s}'", .{ f.new, f.old }));
        }
        try j.endObject();
    }
    try j.endArray();
    try j.endObject();
    return j.finish();
}

/// The problems and warnings as a GitLab Code Quality report, which a job
/// keeps as an artifact (`artifacts: reports: codequality:`) and GitLab
/// shows on the merge request: a JSON array of findings
pub fn renderGitlab(self: *Report, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    const Json = @import("output/Json.zig");
    var j: Json = .{ .arena = arena };
    try j.beginArray();
    for (try self.sorted(arena)) |l| {
        try j.beginObject();
        try j.key("description");
        try j.string(l.p.message);
        try j.key("check_name");
        try j.string("skein");
        try j.key("fingerprint");
        const id = try arena.print("{s}:{d}:{d}:{s}:{s}", .{ l.p.file, l.p.line, l.p.column, l.kind, l.p.message });
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(id, &digest, .{});
        try j.string(&std.fmt.bytesToHex(digest[0..16].*, .lower));
        try j.key("severity");
        try j.string(if (std.mem.eql(u8, l.kind, "error")) "major" else "minor");
        try j.key("location");
        try j.beginObject();
        try j.key("path");
        try j.string(l.p.file);
        try j.key("lines");
        try j.beginObject();
        try j.key("begin");
        try j.integer(@max(l.p.line, 1));
        try j.endObject();
        try j.endObject();
        try j.endObject();
    }
    try j.endArray();
    return j.finish();
}

const Line = struct { p: Problem, kind: []const u8 };

/// The problems and warnings together, in order of file and place
fn sorted(self: *const Report, arena: std.mem.Allocator) std.mem.Allocator.Error![]const Line {
    var lines: std.ArrayList(Line) = .empty;
    for (self.problems.items) |p| try lines.append(arena, .{ .p = p, .kind = "error" });
    for (self.warnings.items) |p| try lines.append(arena, .{ .p = p, .kind = "warning" });
    std.mem.sort(Line, lines.items, {}, struct {
        fn lt(_: void, a: Line, b: Line) bool {
            return before({}, a.p, b.p);
        }
    }.lt);
    return lines.items;
}

fn before(_: void, a: Problem, b: Problem) bool {
    return switch (std.mem.order(u8, a.file, b.file)) {
        .lt => true,
        .gt => false,
        .eq => if (a.line != b.line) a.line < b.line else if (a.column != b.column) a.column < b.column else std.mem.lessThan(u8, a.message, b.message),
    };
}

// req: check.report, principle.deterministic
test "problems are rendered in order of file and place" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var report: Report = .{ .arena = arena.allocator() };
    try report.add("b.toml", 3, 1, "second {s}", .{"thing"});
    try report.add("b.toml", 1, 4, "first", .{});
    try report.add("a.toml", 0, 0, "whole file", .{});
    try std.testing.expect(!report.ok());
    try std.testing.expectEqualStrings(
        \\a.toml: error: whole file
        \\b.toml:1:4: error: first
        \\b.toml:3:1: error: second thing
        \\
    , try report.render(arena.allocator()));
}

// req: check.warnings
test "warnings are rendered among the problems and fail nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var report: Report = .{ .arena = arena.allocator() };
    try report.warn("a.toml", 2, 1, "not checked", .{});
    try std.testing.expect(report.ok());
    try report.add("a.toml", 1, 1, "wrong", .{});
    try std.testing.expectEqualStrings(
        \\a.toml:1:1: error: wrong
        \\a.toml:2:1: warning: not checked
        \\
    , try report.render(arena.allocator()));
}
