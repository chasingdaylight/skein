//! The problems a command found, each with the file (and place) it is in.

const std = @import("std");

const Report = @This();

arena: std.mem.Allocator,
problems: std.ArrayList(Problem) = .empty,

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
    try self.problems.append(self.arena, .{
        .file = try self.arena.dupe(u8, file),
        .line = line,
        .column = column,
        .message = try self.arena.print(fmt, args),
    });
}

pub fn ok(self: *const Report) bool {
    return self.problems.items.len == 0;
}

/// The problems as text, one per line (`file:line:column: error: message`),
/// ordered by file and place.
pub fn render(self: *Report, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    std.mem.sort(Problem, self.problems.items, {}, before);
    var out: std.ArrayList(u8) = .empty;
    for (self.problems.items) |p| {
        try out.appendSlice(arena, p.file);
        if (p.line > 0) try out.print(arena, ":{d}:{d}", .{ p.line, p.column });
        try out.print(arena, ": error: {s}\n", .{p.message});
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
