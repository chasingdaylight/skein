//! References to items in prose: `%[lex.comment.line]`, or with the words
//! to show after the ID, `%[lex.comment.line line comments]`. It is a
//! marker without an item type: one that names an item and declares none.
//! Nothing inside a code span or a code block is a reference.

const std = @import("std");

const blocks = @import("blocks.zig");

pub const Reference = struct {
    target: []const u8,
    /// the words to show in place of the ID, when given
    display: ?[]const u8 = null,
    /// of the percent sign in the text that was searched
    offset: usize,
};

/// The references in `text`, which is Markdown: one block or several.
pub fn find(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const Reference {
    var out: std.ArrayList(Reference) = .empty;
    // code blocks are found as the document's scanner finds them
    for (try blocks.scan(arena, text)) |block| {
        if (block.kind == .code or block.kind == .front_matter or block.kind == .yaml_front_matter) continue;
        const base = @intFromPtr(block.text.ptr) - @intFromPtr(text.ptr);
        try findInline(arena, block.text, base, &out);
    }
    return out.items;
}

fn findInline(arena: std.mem.Allocator, text: []const u8, base: usize, out: *std.ArrayList(Reference)) !void {
    var i: usize = 0;
    while (i < text.len) {
        switch (text[i]) {
            '\\' => i += 2,
            '`' => i = skipCodeSpan(text, i),
            '%' => {
                // not after a letter or a digit: `50%[1]` is a number and a note
                const stands_alone = i == 0 or !std.ascii.isAlphanumeric(text[i - 1]);
                if (stands_alone and i + 1 < text.len and text[i + 1] == '[') {
                    if (parseAt(text, i)) |found| {
                        var r = found.reference;
                        r.offset = base + i;
                        try out.append(arena, r);
                        i = found.end;
                        continue;
                    }
                }
                i += 1;
            },
            else => i += 1,
        }
    }
}

/// After the code span that the backticks at `i` open; after the
/// backticks alone when nothing closes them
fn skipCodeSpan(text: []const u8, i: usize) usize {
    var n: usize = 0;
    while (i + n < text.len and text[i + n] == '`') n += 1;
    var j = i + n;
    while (j < text.len) {
        if (text[j] != '`') {
            j += 1;
            continue;
        }
        var m: usize = 0;
        while (j + m < text.len and text[j + m] == '`') m += 1;
        if (m == n) return j + m;
        j += m;
    }
    return i + n;
}

/// The reference whose `%[` is at `i`; null when what follows is not one
fn parseAt(text: []const u8, i: usize) ?struct { reference: Reference, end: usize } {
    const start = i + 2;
    const close = std.mem.findScalarPos(u8, text, start, ']') orelse return null;
    const inner = std.mem.trim(u8, text[start..close], " ");
    if (std.mem.findScalar(u8, inner, '\n') != null or std.mem.findScalar(u8, inner, '[') != null) return null;
    // the ID is the first word, as in a marker
    const space = std.mem.findScalar(u8, inner, ' ');
    const target = if (space) |s| inner[0..s] else inner;
    if (target.len == 0) return null;
    for (target) |c| {
        // '#' and '/' for an issue or pull request: `#97`, `owner/repo#12`
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '_' and c != ':' and c != '#' and c != '/') return null;
    }
    const display: ?[]const u8 = if (space) |s| std.mem.trim(u8, inner[s + 1 ..], " ") else null;
    return .{
        .reference = .{ .target = target, .display = display, .offset = 0 },
        .end = close + 1,
    };
}

/// The line (1-based) and column of `offset` in `text`
pub fn position(text: []const u8, offset: usize) struct { line: u32, column: u32 } {
    var line: u32 = 1;
    var column: u32 = 1;
    for (text[0..@min(offset, text.len)]) |c| {
        if (c == '\n') {
            line += 1;
            column = 1;
        } else column += 1;
    }
    return .{ .line = line, .column = column };
}

// req: items.reference
const testing = std.testing;

fn expectTargets(text: []const u8, expected: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try find(arena.allocator(), text);
    try testing.expectEqual(expected.len, got.len);
    for (got, expected) |g, e| try testing.expectEqualStrings(e, g.target);
}

test "references, with and without words to show" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const text = "A %[lex.token] is read, as %[ lex.space  white space ] is not.\nSee %[SRS-012].";
    const got = try find(arena.allocator(), text);
    try testing.expectEqual(3, got.len);
    try testing.expectEqualStrings("lex.token", got[0].target);
    try testing.expectEqual(null, got[0].display);
    try testing.expectEqualStrings("lex.space", got[1].target);
    try testing.expectEqualStrings("white space", got[1].display.?);
    try testing.expectEqualStrings("SRS-012", got[2].target);
    const p = position(text, got[2].offset);
    try testing.expectEqual(2, p.line);
    try testing.expectEqual(5, p.column);
}

test "nothing in code is a reference" {
    try expectTargets("Write `%[not.this]` or ``a ` %[nor.this]`` but %[this.one].", &.{"this.one"});
    try expectTargets("Text %[a.b].\n\n```\n%[in.a.block]\n```\n\n    %[indented.code]\n\nMore %[c.d].", &.{ "a.b", "c.d" });
    try expectTargets("An unclosed ` backtick, then %[still.found].", &.{"still.found"});
}

test "what looks like a reference and is not" {
    try expectTargets("\\%[escaped] and %[] and %[two, words] and %[open", &.{});
    try expectTargets("a rise of 50%[1] and x%[i]", &.{});
    try expectTargets("%[split\nover.lines]", &.{});
    // the brackets of other tools are theirs: a page of a wiki, a link
    try expectTargets("See [[lexical]], [[spec/index|the start]] and [a link][ref].", &.{});
}

test "a reference at the start of a paragraph declares nothing" {
    try expectTargets("%[lex.token] is the word for it.", &.{"lex.token"});
    const marker = @import("Marker.zig");
    try testing.expect(!marker.startsOne("%[lex.token] is the word for it."));
}

test "a reference into another repository" {
    try expectTargets("See %[compiler:expr.as.narrow].", &.{"compiler:expr.as.narrow"});
}
