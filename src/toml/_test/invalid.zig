//! Documents the parser must refuse, and where it says the mistake is.

const std = @import("std");
const testing = std.testing;

const toml = @import("../../toml.zig");

/// Expects `source` refused at `line` and `column`
fn refused(source: []const u8, line: u32, column: u32) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: toml.Diagnostic = .{};
    try testing.expectError(error.InvalidToml, toml.parse(arena.allocator(), source, &diag));
    try testing.expect(diag.message.len > 0);
    testing.expectEqual(line, diag.line) catch |e| {
        std.debug.print("{d}:{d}: {s}\n", .{ diag.line, diag.column, diag.message });
        return e;
    };
    try testing.expectEqual(column, diag.column);
}

/// Expects `source` refused, wherever
fn refusedSomewhere(source: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: toml.Diagnostic = .{};
    testing.expectError(error.InvalidToml, toml.parse(arena.allocator(), source, &diag)) catch |e| {
        std.debug.print("accepted: {s}\n", .{source});
        return e;
    };
}

test "keys and values that are missing or doubled" {
    try refused("key = # nothing", 1, 7);
    try refused("= 1", 1, 1);
    try refused("a 1", 1, 3);
    try refused("a = 1 b = 2", 1, 7);
    try refused("a = 1\na = 2", 2, 1);
    try refused("a = 1\n\"a\" = 2", 2, 1);
}

test "dotted keys cannot reach into what is defined" {
    try refused("a = 1\na.b = 2", 2, 1);
    try refused("[a]\nb = 1\n[c]\nx = 1\n[a.b]", 5, 1);
    try refused("a = { b = 1 }\na.c = 2", 2, 1);
    try refused("[fruit]\napple.color = 'red'\n[fruit.apple]", 3, 1);
}

test "tables defined twice, or over another value" {
    try refused("[a]\n[a]", 2, 1);
    try refused("a = 1\n[a]", 2, 1);
    try refused("a = [1]\n[[a]]", 2, 1);
    try refused("[a]\n[[a]]", 2, 1);
    try refused("[[a]]\n[a]", 2, 1);
    try refused("a = { b = 1 }\n[a.c]", 2, 1);
    try refused("[a", 1, 3);
    try refused("[[a]", 1, 5);
    try refused("[]", 1, 2);
}

test "strings that are not closed or hold what they may not" {
    try refused("a = \"abc", 1, 9);
    try refused("a = \"abc\nb = 1", 1, 9);
    try refused("a = 'abc", 1, 9);
    try refused("a = \"\"\"abc", 1, 11);
    try refused("a = \"\\q\"", 1, 7);
    try refused("a = \"\\u12\"", 1, 8);
    try refused("a = \"\\uD800\"", 1, 8);
    try refused("a = \"bell \x07\"", 1, 11);
}

test "numbers" {
    for ([_][]const u8{
        "a = 01",                  "a = 1__0", "a = _1",   "a = 1_",   "a = 1.",
        "a = .5",                  "a = 1.e3", "a = 0x",   "a = 0xZZ", "a = +0x1",
        "a = 0b102",               "a = 1e",   "a = 1_.5", "a = +",    "a = Inf",
        "a = 9223372036854775808", "a = 1 2",  "a = 0o8",  "a = --1",
    }) |source| try refusedSomewhere(source);
}

test "dates and times" {
    for ([_][]const u8{
        "a = 2023-02-29",          "a = 2023-13-01",                "a = 2023-00-10",
        "a = 2023-01-01T24:00:00", "a = 2023-01-01T10:60",          "a = 07:32:00Z",
        "a = 2023-01-01T",         "a = 2023-01-01T10:00:00+25:00", "a = 2023-1-01",
        "a = 10:00:00.",
    }) |source| try refusedSomewhere(source);
}

test "arrays and inline tables that are not closed or lack commas" {
    try refused("a = [1, 2", 1, 10);
    try refused("a = [1 2]", 1, 8);
    try refused("a = { b = 1", 1, 12);
    try refused("a = { b = 1 c = 2 }", 1, 13);
    try refused("a = { b = 1, b = 2 }", 1, 14);
}

test "line ends and encoding" {
    try refused("a = 1\rb = 2", 1, 6);
    try refused("a = \"\xff\"", 1, 1);
}
