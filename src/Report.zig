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
};

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
    const Line = struct { p: Problem, kind: []const u8 };
    var lines: std.ArrayList(Line) = .empty;
    for (self.problems.items) |p| try lines.append(arena, .{ .p = p, .kind = "error" });
    for (self.warnings.items) |p| try lines.append(arena, .{ .p = p, .kind = "warning" });
    std.mem.sort(Line, lines.items, {}, struct {
        fn lt(_: void, a: Line, b: Line) bool {
            return before({}, a.p, b.p);
        }
    }.lt);
    var out: std.ArrayList(u8) = .empty;
    for (lines.items) |l| {
        try out.appendSlice(arena, l.p.file);
        if (l.p.line > 0) try out.print(arena, ":{d}:{d}", .{ l.p.line, l.p.column });
        try out.print(arena, ": {s}: {s}\n", .{ l.kind, l.p.message });
    }
    return out.items;
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
