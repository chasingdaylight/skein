//! The block scanner, on Markdown as documents write it.

const std = @import("std");
const testing = std.testing;

const blocks = @import("../blocks.zig");
const Kind = blocks.Block.Kind;

/// Expects `source` to split into blocks of `kinds`, on `lines` (first
/// and last of each)
fn expectBlocks(source: []const u8, kinds: []const Kind, lines: []const [2]u32) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try blocks.scan(arena.allocator(), source, &.{ "rule", "term" });
    var got_kinds: std.ArrayList(Kind) = .empty;
    for (got) |b| try got_kinds.append(arena.allocator(), b.kind);
    try testing.expectEqualSlices(Kind, kinds, got_kinds.items);
    for (got, lines) |b, l| {
        testing.expectEqual(l, [2]u32{ b.first_line, b.last_line }) catch |e| {
            std.debug.print("block {s}: lines {d} to {d}\n", .{ @tagName(b.kind), b.first_line, b.last_line });
            return e;
        };
    }
}

fn scanOne(arena: *std.heap.ArenaAllocator, source: []const u8, index: usize) !blocks.Block {
    const got = try blocks.scan(arena.allocator(), source, &.{"rule"});
    return got[index];
}

test "an empty file has no blocks" {
    try expectBlocks("", &.{}, &.{});
    try expectBlocks("\n\n  \n", &.{}, &.{});
}

test "headings, paragraphs and blank lines" {
    try expectBlocks(
        \\# Title
        \\
        \\One paragraph
        \\over two lines.
        \\
        \\
        \\## Section
        \\Text right after it.
        \\#hashtag is text
    , &.{ .heading, .paragraph, .heading, .paragraph }, &.{ .{ 1, 1 }, .{ 3, 4 }, .{ 7, 7 }, .{ 8, 9 } });
}

test "a marker is a block of its own, wherever it stands" {
    try expectBlocks(
        \\rule[lex.comment.line] legality
        \\A line comment starts with two slashes.
        \\
        \\Text before
        \\rule[lex.comment.block]
        \\
        \\A block comment is delimited.
        \\array[i] is not a marker
    , &.{ .marker, .paragraph, .paragraph, .marker, .paragraph }, &.{ .{ 1, 1 }, .{ 2, 2 }, .{ 4, 4 }, .{ 5, 5 }, .{ 7, 8 } });
}

test "fenced code keeps everything inside, markers and blank lines too" {
    try expectBlocks(
        \\Text.
        \\```text
        \\rule[not.a.marker]
        \\
        \\# not a heading
        \\```
        \\After.
        \\~~~~
        \\``` inside tildes
        \\~~~
        \\~~~~
    , &.{ .paragraph, .code, .paragraph, .code }, &.{ .{ 1, 1 }, .{ 2, 6 }, .{ 7, 7 }, .{ 8, 11 } });
}

test "a fence that is never closed runs to the end" {
    try expectBlocks("```\ncode\n\nmore", &.{.code}, &.{.{ 1, 4 }});
}

test "indented code, over blank lines" {
    try expectBlocks(
        \\Text.
        \\
        \\    code one
        \\
        \\    code two
        \\
        \\Text again.
    , &.{ .paragraph, .code, .paragraph }, &.{ .{ 1, 1 }, .{ 3, 5 }, .{ 7, 7 } });
}

test "lists: loose items, nested text, and where they end" {
    try expectBlocks(
        \\The keywords are:
        \\- `as`
        \\- `fn`
        \\
        \\- `let`, after a blank line
        \\
        \\  with a second paragraph
        \\
        \\Not in the list.
        \\
        \\1. one
        \\2) two
        \\rule[after.list]
    , &.{ .paragraph, .list, .paragraph, .list, .marker }, &.{ .{ 1, 1 }, .{ 2, 7 }, .{ 9, 9 }, .{ 11, 12 }, .{ 13, 13 } });
}

test "a number other than one does not cut a paragraph short" {
    try expectBlocks("It was\n1987. A year\n- and a bullet", &.{ .paragraph, .list }, &.{ .{ 1, 2 }, .{ 3, 3 } });
}

test "quotes, tables, thematic breaks and HTML" {
    try expectBlocks(
        \\> quoted
        \\> more
        \\
        \\| a | b |
        \\| - | - |
        \\| 1 | 2 |
        \\
        \\---
        \\* * *
        \\<!-- a comment
        \\
        \\over a blank line -->
        \\<div>
        \\html
        \\</div>
        \\
        \\Text.
    , &.{ .quote, .table, .thematic_break, .thematic_break, .html, .html, .paragraph }, &.{ .{ 1, 2 }, .{ 4, 6 }, .{ 8, 8 }, .{ 9, 9 }, .{ 10, 12 }, .{ 13, 15 }, .{ 17, 17 } });
}

test "front matter is the TOML between the first two +++ lines" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "+++\nid = \"SRS-001\"\ntype = \"srs\"\n+++\n\nThe body.\n";
    const fm = try scanOne(&arena, source, 0);
    try testing.expectEqual(.front_matter, fm.kind);
    try testing.expectEqual(4, fm.last_line);
    // the text starts at the end of line 1, so its lines count as the file's
    try testing.expectEqualStrings("\nid = \"SRS-001\"\ntype = \"srs\"", fm.text);
    const body = try scanOne(&arena, source, 1);
    try testing.expectEqual(.paragraph, body.kind);
    try testing.expectEqual(6, body.first_line);
    try testing.expectEqualStrings("The body.", body.text);
}

test "front matter: empty, not at the top, not closed" {
    try expectBlocks("+++\n+++\nText.", &.{ .front_matter, .paragraph }, &.{ .{ 1, 2 }, .{ 3, 3 } });
    try expectBlocks("Text.\n\n+++\nx = 1\n+++", &.{ .paragraph, .paragraph }, &.{ .{ 1, 1 }, .{ 3, 5 } });
    try expectBlocks("+++\nx = 1\n\nText.", &.{ .paragraph, .paragraph }, &.{ .{ 1, 2 }, .{ 4, 4 } });
}

test "line ends: CRLF gives the same blocks, and no carriage return in the text" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const b = try scanOne(&arena, "# Title\r\n\r\nOne\r\ntwo.\r\n", 1);
    try testing.expectEqual(.paragraph, b.kind);
    try testing.expectEqualStrings("One\r\ntwo.", b.text);
    try testing.expectEqual(4, b.last_line);
}
