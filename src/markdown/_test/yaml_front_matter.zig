//! Files that start with YAML front matter, as site generators want.

const std = @import("std");
const testing = std.testing;

const blocks = @import("../blocks.zig");
const Kind = blocks.Block.Kind;

fn kinds(arena: std.mem.Allocator, source: []const u8) ![]const Kind {
    var out: std.ArrayList(Kind) = .empty;
    for (try blocks.scan(arena, source, &.{"rule"})) |b| try out.append(arena, b.kind);
    return out.items;
}

test "YAML front matter is one block, and what follows is read as ever" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\---
        \\title: "Lexical structure"
        \\tags: ["spec"]
        \\rule[not.a.marker]
        \\---
        \\
        \\## Comments
        \\
        \\rule[lex.comment]
        \\A comment.
    ;
    try testing.expectEqualSlices(Kind, &.{ .yaml_front_matter, .heading, .marker, .paragraph }, try kinds(a, source));
    const all = try blocks.scan(a, source, &.{"rule"});
    try testing.expectEqual(5, all[0].last_line);
    try testing.expectEqual(9, all[2].first_line);
}

test "three dashes that are not front matter" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // not closed: a thematic break and text
    try testing.expectEqualSlices(Kind, &.{ .thematic_break, .paragraph, .paragraph }, try kinds(a, "---\ntitle: x\n\nText."));
    // not at the top
    try testing.expectEqualSlices(Kind, &.{ .paragraph, .thematic_break, .paragraph, .thematic_break }, try kinds(a, "Text.\n\n---\nmore\n\n---"));
}
