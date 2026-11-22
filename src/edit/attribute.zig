//! Writing an attribute an item does not have yet: `key=value` at the end
//! of its marker, or `key = "value"` in its front matter after its ID.

const std = @import("std");

const Marker = @import("../markdown/Marker.zig");

const Error = std.mem.Allocator.Error;

/// `text` with `key=value` added to the marker on line `number` (1-based);
/// null when the line has no marker skein can change
pub fn marker(arena: std.mem.Allocator, text: []const u8, number: u32, key: []const u8, value: []const u8) Error!?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: u32 = 1;
    var done = false;
    while (lines.next()) |line| : (n += 1) {
        if (n > 1) try out.append(arena, '\n');
        if (n != number) {
            try out.appendSlice(arena, line);
            continue;
        }
        const start = Marker.startIn(line) orelse return null;
        const end = start + Marker.extent(line[start..]);
        if (end == 0 or line[end - 1] != ']') return null;
        try out.print(arena, "{s} {s}={s}{s}", .{ line[0 .. end - 1], key, value, line[end - 1 ..] });
        done = true;
    }
    return if (done) out.items else null;
}

/// `text`, an item file with TOML front matter (`+++`), with
/// `key = "value"` added after its ID; null when it has no such front
/// matter or no `id` line in it
pub fn frontMatter(arena: std.mem.Allocator, text: []const u8, key: []const u8, value: []const u8) Error!?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var kept: std.ArrayList([]const u8) = .empty;
    var in_front = false;
    var added = false;
    var n: usize = 0;
    while (lines.next()) |line| : (n += 1) {
        const bare = std.mem.trim(u8, line, " \t\r");
        if (n == 0) {
            if (!std.mem.eql(u8, bare, "+++")) return null;
            in_front = true;
        } else if (in_front and std.mem.eql(u8, bare, "+++")) in_front = false;
        try kept.append(arena, line);
        if (in_front and !added and (std.mem.startsWith(u8, bare, "id ") or std.mem.startsWith(u8, bare, "id="))) {
            const cr = if (std.mem.endsWith(u8, line, "\r")) "\r" else "";
            try kept.append(arena, try arena.print("{s} = \"{s}\"{s}", .{ key, value, cr }));
            added = true;
        }
    }
    if (!added) return null;
    return try std.mem.join(arena, "\n", kept.items);
}

const testing = std.testing;

test marker {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = (try marker(a, "# T\n%task[t.a days=2] Text.\n", 2, "mode", "float")).?;
    try testing.expectEqualStrings("# T\n%task[t.a days=2 mode=float] Text.\n", out);
    try testing.expectEqual(null, try marker(a, "no marker\n", 1, "mode", "float"));
}

test frontMatter {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const out = (try frontMatter(arena.allocator(), "+++\r\nid = \"t.a\"\r\ndays = 2\r\n+++\r\nText.\r\n", "mode", "float")).?;
    try testing.expectEqualStrings("+++\r\nid = \"t.a\"\r\nmode = \"float\"\r\ndays = 2\r\n+++\r\nText.\r\n", out);
    try testing.expectEqual(null, try frontMatter(arena.allocator(), "Text.\n", "mode", "float"));
}
