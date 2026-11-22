//! Writing a former ID into an item's marker or front matter, so that
//! what names the item from outside still finds it (`skein move`).

const std = @import("std");

const Marker = @import("../markdown/Marker.zig");

const Error = std.mem.Allocator.Error;

/// `line`, which has the marker of an item, with `old` added to the
/// marker's aliases
pub fn marker(arena: std.mem.Allocator, line: []const u8, old: []const u8) Error![]const u8 {
    const start = Marker.startIn(line) orelse return line;
    const end = start + Marker.extent(line[start..]);
    if (end == 0 or line[end - 1] != ']') return line;
    const close = end - 1;
    if (std.mem.find(u8, line[start..close], " aliases=")) |at| {
        const from = start + at + 1;
        const word_end = std.mem.findScalarPos(u8, line[0..close], from, ' ') orelse close;
        return arena.print("{s},{s}{s}", .{ line[0..word_end], old, line[word_end..] });
    }
    return arena.print("{s} aliases={s}{s}", .{ line[0..close], old, line[close..] });
}

/// `text`, an item file with TOML front matter, with `old` added to its
/// `aliases`
pub fn frontMatter(arena: std.mem.Allocator, text: []const u8, old: []const u8) Error![]const u8 {
    if (!std.mem.startsWith(u8, text, "+++")) return text;
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    var number: usize = 0;
    var done = false;
    var inside = true;
    var after_id: ?usize = null;
    var lines: std.ArrayList([]const u8) = .empty;
    while (it.next()) |line| : (number += 1) try lines.append(arena, line);
    for (lines.items, 0..) |line, i| {
        const bare = std.mem.trimEnd(u8, line, " \t\r");
        if (i > 0 and inside and std.mem.eql(u8, bare, "+++")) inside = false;
        if (inside and !done and std.mem.startsWith(u8, bare, "aliases") and std.mem.endsWith(u8, bare, "]")) {
            const close = std.mem.findScalarLast(u8, line, ']').?;
            const empty = std.mem.endsWith(u8, std.mem.trimEnd(u8, line[0..close], " "), "[");
            lines.items[i] = try arena.print("{s}{s}\"{s}\"{s}", .{ line[0..close], if (empty) "" else ", ", old, line[close..] });
            done = true;
        }
        if (inside and after_id == null and std.mem.startsWith(u8, bare, "id")) after_id = i;
    }
    for (lines.items, 0..) |line, i| {
        if (i > 0) try out.append(arena, '\n');
        try out.appendSlice(arena, line);
        if (!done and i == (after_id orelse 0)) {
            const crlf = std.mem.endsWith(u8, line, "\r");
            try out.print(arena, "\naliases = [\"{s}\"]{s}", .{ old, if (crlf) "\r" else "" });
            done = true;
        }
    }
    return out.items;
}

// req: move.aliases
test "a former ID is added to a marker" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("%rule[lex.new syntax aliases=lex.old] Text.", try marker(a, "%rule[lex.new syntax] Text.", "lex.old"));
    try std.testing.expectEqualStrings("- %rule[.b aliases=x.a,x.b.old] Text.", try marker(a, "- %rule[.b aliases=x.a] Text.", "x.b.old"));
    try std.testing.expectEqualStrings("%rule[a aliases=b,c stage=s0]", try marker(a, "%rule[a aliases=b stage=s0]", "c"));
}

test "a former ID is added to front matter" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("+++\nid = \"SRS-2\"\naliases = [\"SRS-1\"]\n+++\nText.\n", try frontMatter(a, "+++\nid = \"SRS-2\"\n+++\nText.\n", "SRS-1"));
    try std.testing.expectEqualStrings("+++\naliases = [\"A\", \"B\"]\n+++\n", try frontMatter(a, "+++\naliases = [\"A\"]\n+++\n", "B"));
    try std.testing.expectEqualStrings("+++\r\nid = \"X\"\r\naliases = [\"Y\"]\r\n+++\r\n", try frontMatter(a, "+++\r\nid = \"X\"\r\n+++\r\n", "Y"));
}
