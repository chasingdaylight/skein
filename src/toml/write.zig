//! Writing TOML values, for the files skein writes.

const std = @import("std");

/// `s` as a TOML string: on one line, or between `"""` when it has
/// several lines
pub fn string(arena: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    const multiline = std.mem.findScalar(u8, s, '\n') != null;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, if (multiline) "\"\"\"\n" else "\"");
    for (s) |c| switch (c) {
        '"' => try out.appendSlice(arena, "\\\""),
        '\\' => try out.appendSlice(arena, "\\\\"),
        '\n' => try out.append(arena, '\n'),
        '\t' => try out.appendSlice(arena, "\\t"),
        '\r' => {},
        0...8, 11, 12, 14...0x1f, 0x7f => try out.print(arena, "\\u{x:0>4}", .{c}),
        else => try out.append(arena, c),
    };
    try out.appendSlice(arena, if (multiline) "\"\"\"" else "\"");
    return out.items;
}

/// `items` as a TOML array of strings, on one line
pub fn strings(arena: std.mem.Allocator, items: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '[');
    for (items, 0..) |item, i| {
        if (i > 0) try out.appendSlice(arena, ", ");
        try out.appendSlice(arena, try string(arena, item));
    }
    try out.append(arena, ']');
    return out.items;
}

test "strings are written so that they read back the same" {
    const toml = @import("../toml.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{
        "plain",
        "",
        "a \"quoted\" word and a back\\slash",
        "tab\there",
        "two lines\nand \"\"\" three quotes\nand a third",
        "ends with a line end\n",
    }) |s| {
        const doc = try a.print("a = {s}\nb = {s}\n", .{ try string(a, s), try strings(a, &.{ s, "x" }) });
        var diag: toml.Diagnostic = .{};
        const table = toml.parse(a, doc, &diag) catch |e| {
            std.debug.print("{d}:{d}: {s}\n{s}\n", .{ diag.line, diag.column, diag.message, doc });
            return e;
        };
        try std.testing.expectEqualStrings(s, table.get("a").?.string);
        try std.testing.expectEqualStrings(s, table.get("b").?.array.values()[0].string);
    }
}
