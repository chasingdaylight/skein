//! Just enough HTML for the pages of NPR 7150.2D on NODIS: the blocks of a
//! chapter's content (headings, paragraphs, notes, tables) and their text.

const std = @import("std");

pub const Kind = enum { heading1, heading2, paragraph, note, table };

pub const Block = struct {
    kind: Kind,
    /// the text, with entities decoded and tags left out; a line break
    /// where the page has `<br>`
    text: []const u8 = "",
    /// a table's rows of cells
    rows: []const []const []const u8 = &.{},
};

const Error = std.mem.Allocator.Error;

/// The blocks of a chapter page: from its `<h1>` to the footer
pub fn blocks(arena: std.mem.Allocator, page: []const u8) Error![]const Block {
    var out: std.ArrayList(Block) = .empty;
    var at = std.mem.find(u8, page, "<h1>") orelse return &.{};
    const end = std.mem.find(u8, page, "Begin Stan_dard Footer") orelse page.len;
    while (std.mem.findScalarPos(u8, page[0..end], at, '<')) |open| {
        const rest = page[open..end];
        const Tag = struct { start: []const u8, close: []const u8, kind: Kind };
        const tags = [_]Tag{
            .{ .start = "<h1", .close = "</h1>", .kind = .heading1 },
            .{ .start = "<h2", .close = "</h2>", .kind = .heading2 },
            .{ .start = "<p", .close = "</p>", .kind = .paragraph },
            .{ .start = "<table", .close = "</table>", .kind = .table },
        };
        const tag = for (tags) |t| {
            if (std.mem.startsWith(u8, rest, t.start) and rest.len > t.start.len and (rest[t.start.len] == '>' or rest[t.start.len] == ' ')) break t;
        } else {
            at = open + 1;
            continue;
        };
        const head_end = std.mem.findScalarPos(u8, rest, 0, '>') orelse break;
        const close = std.mem.find(u8, rest, tag.close) orelse break;
        const inner = rest[head_end + 1 .. close];
        at = open + close + tag.close.len;
        var kind = tag.kind;
        if (kind == .paragraph and std.mem.find(u8, rest[0..head_end], "font-style: italic") != null) kind = .note;
        if (kind == .table) {
            try out.append(arena, .{ .kind = .table, .rows = try rows(arena, inner) });
            continue;
        }
        const text = try inlineText(arena, inner);
        if (text.len > 0) try out.append(arena, .{ .kind = kind, .text = text });
    }
    return out.items;
}

/// The rows of a table, each its cells' text
pub fn rows(arena: std.mem.Allocator, table: []const u8) Error![]const []const []const u8 {
    var out: std.ArrayList([]const []const u8) = .empty;
    var at: usize = 0;
    while (std.mem.findPos(u8, table, at, "<tr")) |open| {
        const close = std.mem.findPos(u8, table, open, "</tr>") orelse table.len;
        try out.append(arena, try cells(arena, table[open..close]));
        at = close;
    }
    return out.items;
}

/// The text of each `<td>` or `<th>` of a row
pub fn cells(arena: std.mem.Allocator, row: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var at: usize = 0;
    while (std.mem.findScalarPos(u8, row, at, '<')) |open| {
        at = open + 1;
        const is_cell = std.mem.startsWith(u8, row[open..], "<td") or std.mem.startsWith(u8, row[open..], "<th");
        if (!is_cell) continue;
        const head_end = std.mem.findScalarPos(u8, row, open, '>') orelse break;
        const close_tag = if (row[open + 2] == 'd') "</td>" else "</th>";
        const close = std.mem.findPos(u8, row, head_end, close_tag) orelse row.len;
        try out.append(arena, try inlineText(arena, row[head_end + 1 .. close]));
        at = close;
    }
    return out.items;
}

/// `fragment` as text: tags left out (`<br>` a line break), entities
/// decoded, runs of white space one space, lines trimmed
pub fn inlineText(arena: std.mem.Allocator, fragment: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    var space = false;
    while (i < fragment.len) {
        const c = fragment[i];
        if (c == '<') {
            const close = std.mem.findScalarPos(u8, fragment, i, '>') orelse fragment.len - 1;
            if (std.ascii.startsWithIgnoreCase(fragment[i..], "<br")) {
                trimEnd(&out);
                try out.append(arena, '\n');
                space = false;
            }
            i = close + 1;
            continue;
        }
        if (c == '&') if (entity(fragment[i..])) |e| {
            if (std.mem.eql(u8, e.text, " ")) {
                space = true;
            } else {
                if (space and out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(arena, ' ');
                space = false;
                try out.appendSlice(arena, e.text);
            }
            i += e.len;
            continue;
        };
        if (std.ascii.isWhitespace(c)) {
            space = true;
            i += 1;
            continue;
        }
        if (space and out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(arena, ' ');
        space = false;
        try out.append(arena, c);
        i += 1;
    }
    trimEnd(&out);
    return std.mem.trim(u8, out.items, " \n");
}

fn trimEnd(out: *std.ArrayList(u8)) void {
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items.len -= 1;
}

const Entity = struct { text: []const u8, len: usize };

/// The entity `s` starts with, decoded; null for one not known here
fn entity(s: []const u8) ?Entity {
    const end = std.mem.findScalar(u8, s[0..@min(s.len, 10)], ';') orelse return null;
    const name = s[1..end];
    const table = [_]struct { []const u8, []const u8 }{
        .{ "amp", "&" },          .{ "lt", "<" },            .{ "gt", ">" },
        .{ "quot", "\"" },        .{ "nbsp", " " },          .{ "ldquo", "\u{201C}" },
        .{ "rdquo", "\u{201D}" }, .{ "lsquo", "\u{2018}" },  .{ "rsquo", "\u{2019}" },
        .{ "ndash", "\u{2013}" }, .{ "hellip", "\u{2026}" }, .{ "reg", "\u{00AE}" },
        .{ "sect", "\u{00A7}" },  .{ "bull", "\u{2022}" },
    };
    for (table) |pair| if (std.mem.eql(u8, name, pair[0])) return .{ .text = pair[1], .len = end + 1 };
    return null;
}

const testing = std.testing;

test inlineText {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("IV&V of the project\u{2019}s software", try inlineText(a, "\n IV&amp;V   of the <b>project</b>&rsquo;s\n software "));
    try testing.expectEqualStrings("Class A, B,\nand C", try inlineText(a, "Class A, B, <br>and C"));
}

test blocks {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const page =
        \\<H2>Subject</H2><h1>Chapter 3: Management</h1>
        \\<h2>3.1 Planning</h2>
        \\<p>
        \\3.1.3 The project manager shall plan. [SWE-013]
        \\</p>
        \\<p style="margin: 0.25in; font-style: italic">
        \\Note: Plans.
        \\</p>
        \\<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td></td></tr></table>
        \\<!--  Begin Stan_dard Footer. --><p>after</p>
    ;
    const b = try blocks(arena.allocator(), page);
    try testing.expectEqual(5, b.len);
    try testing.expectEqual(.heading1, b[0].kind);
    try testing.expectEqualStrings("3.1 Planning", b[1].text);
    try testing.expectEqualStrings("3.1.3 The project manager shall plan. [SWE-013]", b[2].text);
    try testing.expectEqual(.note, b[3].kind);
    try testing.expectEqualStrings("", b[4].rows[1][1]);
}
