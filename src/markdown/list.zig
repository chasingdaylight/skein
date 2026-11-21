//! The entries of a list block.

const std = @import("std");

const blocks = @import("blocks.zig");

pub const Entry = struct {
    /// the entry's content: its lines without the bullet and the
    /// indentation under it (a copy), to be read as Markdown of its own
    text: []const u8,
    /// the entry as it stands in the list: a slice of the block's text
    raw: []const u8,
    /// the file's line of the entry's first line
    first_line: u32,
    /// how many columns were taken off each line
    dedent: u32,
};

/// The entries of the list `block`: each starts at a bullet or a number at
/// the list's own indentation, and holds every line up to the next.
pub fn entries(arena: std.mem.Allocator, block: blocks.Block) std.mem.Allocator.Error![]const Entry {
    var out: std.ArrayList(Entry) = .empty;
    const text = block.text;
    const base = blocks.indentOf(text);

    var start: ?usize = null; // offset of the current entry's first line
    var start_line: u32 = 0;
    var offset: usize = 0;
    var line_no: u32 = block.first_line;
    while (offset <= text.len) {
        const nl = std.mem.findScalarPos(u8, text, offset, '\n') orelse text.len;
        const line = text[offset..nl];
        const begins = blocks.indentOf(line) <= base and blocks.isListStart(line);
        if (begins) {
            if (start) |s| try out.append(arena, try entry(arena, text[s..offset], start_line));
            start = offset;
            start_line = line_no;
        }
        if (nl == text.len) break;
        offset = nl + 1;
        line_no += 1;
    }
    if (start) |s| try out.append(arena, try entry(arena, text[s..], start_line));
    return out.items;
}

fn entry(arena: std.mem.Allocator, raw_lines: []const u8, first_line: u32) !Entry {
    const raw = std.mem.trimEnd(u8, raw_lines, " \t\r\n");
    // the first line: indentation, the bullet or number, then spaces
    var col = blocks.indentOf(raw);
    while (col < raw.len and raw[col] != ' ' and raw[col] != '\t' and raw[col] != '\n') col += 1;
    var spaces: usize = 0;
    while (col + spaces < raw.len and raw[col + spaces] == ' ') spaces += 1;
    // more than four spaces after the bullet start an indented code block
    col += if (spaces >= 1 and spaces <= 4) spaces else @min(spaces, 1);

    var text: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    var first = true;
    while (lines.next()) |with_cr| {
        const line = std.mem.trimEnd(u8, with_cr, "\r");
        if (!first) try text.append(arena, '\n');
        if (first) {
            try text.appendSlice(arena, line[@min(col, line.len)..]);
        } else {
            var strip: usize = 0;
            while (strip < col and strip < line.len and line[strip] == ' ') strip += 1;
            try text.appendSlice(arena, line[strip..]);
        }
        first = false;
    }
    return .{ .text = text.items, .raw = raw, .first_line = first_line, .dedent = @intCast(col) };
}

const testing = std.testing;

fn listOf(arena: std.mem.Allocator, source: []const u8) ![]const Entry {
    const all = try blocks.scan(arena, source);
    try testing.expectEqual(.list, all[all.len - 1].kind);
    return entries(arena, all[all.len - 1]);
}

test "entries, with what is nested in them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try listOf(arena.allocator(),
        \\Intro.
        \\
        \\- one
        \\- two, with
        \\  a second line
        \\
        \\  and a paragraph
        \\
        \\  - nested
        \\  - list
        \\-   three
    );
    try testing.expectEqual(3, got.len);
    try testing.expectEqualStrings("one", got[0].text);
    try testing.expectEqual(3, got[0].first_line);
    try testing.expectEqual(2, got[0].dedent);
    try testing.expectEqualStrings("two, with\na second line\n\nand a paragraph\n\n- nested\n- list", got[1].text);
    try testing.expectEqual(4, got[1].first_line);
    try testing.expect(std.mem.startsWith(u8, got[1].raw, "- two, with\n  a second line"));
    try testing.expectEqualStrings("three", got[2].text);
    try testing.expectEqual(11, got[2].first_line);
}

test "numbered entries, and CRLF line ends" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try listOf(arena.allocator(), "1. first\r\n   more\r\n10) tenth\r\n");
    try testing.expectEqual(2, got.len);
    try testing.expectEqualStrings("first\nmore", got[0].text);
    try testing.expectEqual(3, got[0].dedent);
    try testing.expectEqualStrings("tenth", got[1].text);
    try testing.expectEqual(3, got[1].first_line);
}
