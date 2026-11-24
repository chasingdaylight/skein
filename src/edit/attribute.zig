//! Writing an item's attribute or word in place: `key=value` or a bare word
//! in its marker, or `key = value` in its TOML front matter, replacing the
//! one there or adding it.

const std = @import("std");

const Marker = @import("../markdown/Marker.zig");

const Error = std.mem.Allocator.Error;

/// The words inside the brackets of the marker on line `number` (1-based)
/// of `text`, with where the line and the brackets are
const Found = struct {
    /// the line, without its line end
    line: []const u8,
    line_start: usize,
    /// in `line`: after `[`, and at `]`
    open: usize,
    close: usize,
};

fn findMarker(text: []const u8, number: u32) ?Found {
    var at: usize = 0;
    var n: u32 = 1;
    while (n < number) : (n += 1) at = (std.mem.findScalarPos(u8, text, at, '\n') orelse return null) + 1;
    const end = std.mem.findScalarPos(u8, text, at, '\n') orelse text.len;
    const line = text[at..end];
    const start = Marker.startIn(line) orelse return null;
    const span = line[start .. start + Marker.extent(line[start..])];
    const open = std.mem.findScalar(u8, span, '[') orelse return null;
    const close = std.mem.findScalarLast(u8, span, ']') orelse return null;
    return .{ .line = line, .line_start = at, .open = start + open + 1, .close = start + close };
}

/// A word of a marker, by where it is in the line
const Word = struct { start: usize, end: usize };

/// The words of the marker, an ID first; a value in double quotes is one word
fn words(arena: std.mem.Allocator, f: Found) Error![]const Word {
    var out: std.ArrayList(Word) = .empty;
    var i = f.open;
    while (i < f.close) {
        while (i < f.close and f.line[i] == ' ') i += 1;
        if (i >= f.close) break;
        const start = i;
        var quoted = false;
        while (i < f.close and (quoted or f.line[i] != ' ')) : (i += 1) {
            if (f.line[i] == '"') quoted = !quoted;
        }
        try out.append(arena, .{ .start = start, .end = i });
    }
    return out.items;
}

/// `text` with the word that `pick` chooses in the marker on line `number`
/// written as `new`, or `new` added at the end of the marker when it
/// chooses none; null when the line has no marker
fn edit(arena: std.mem.Allocator, text: []const u8, number: u32, pick: anytype, new: []const u8) Error!?[]const u8 {
    const f = findMarker(text, number) orelse return null;
    const ws = try words(arena, f);
    // the ID is never replaced
    for (ws[@min(1, ws.len)..]) |w| {
        if (!pick.matches(f.line[w.start..w.end])) continue;
        const at = f.line_start;
        return try std.mem.concat(arena, u8, &.{ text[0 .. at + w.start], new, text[at + w.end ..] });
    }
    const at = f.line_start + f.close;
    return try std.mem.concat(arena, u8, &.{ text[0..at], " ", new, text[at..] });
}

/// `text` with `key=value` in the marker on line `number` (1-based), in
/// place of the `key=` there; null when the line has no marker
pub fn marker(arena: std.mem.Allocator, text: []const u8, number: u32, key: []const u8, value: []const u8) Error!?[]const u8 {
    const Pick = struct {
        key: []const u8,
        fn matches(self: @This(), w: []const u8) bool {
            return w.len > self.key.len and std.mem.startsWith(u8, w, self.key) and w[self.key.len] == '=';
        }
    };
    return edit(arena, text, number, Pick{ .key = key }, try arena.print("{s}={s}", .{ key, value }));
}

/// `text` with the bare word `new` in the marker on line `number`, in place
/// of the word `old` when it is there; null when the line has no marker
pub fn markerWord(arena: std.mem.Allocator, text: []const u8, number: u32, old: ?[]const u8, new: []const u8) Error!?[]const u8 {
    const Pick = struct {
        old: ?[]const u8,
        fn matches(self: @This(), w: []const u8) bool {
            return self.old != null and std.mem.eql(u8, w, self.old.?);
        }
    };
    return edit(arena, text, number, Pick{ .old = old }, new);
}

/// `text` without the word that `pick` chooses (a `key=` or a bare word) in
/// the marker on line `number`; `text` as it is when the marker has none,
/// null when the line has no marker
fn remove(arena: std.mem.Allocator, text: []const u8, number: u32, pick: anytype) Error!?[]const u8 {
    const f = findMarker(text, number) orelse return null;
    const ws = try words(arena, f);
    for (ws[@min(1, ws.len)..]) |w| {
        if (!pick.matches(f.line[w.start..w.end])) continue;
        // with the space before it
        const at = f.line_start;
        return try std.mem.concat(arena, u8, &.{ text[0 .. at + w.start - 1], text[at + w.end ..] });
    }
    return text;
}

/// `text` without `key=...` in the marker on line `number`
pub fn markerRemove(arena: std.mem.Allocator, text: []const u8, number: u32, key: []const u8) Error!?[]const u8 {
    const Pick = struct {
        key: []const u8,
        fn matches(self: @This(), w: []const u8) bool {
            return w.len > self.key.len and std.mem.startsWith(u8, w, self.key) and w[self.key.len] == '=';
        }
    };
    return remove(arena, text, number, Pick{ .key = key });
}

/// `text` without the bare word `word` in the marker on line `number`
pub fn markerRemoveWord(arena: std.mem.Allocator, text: []const u8, number: u32, word: []const u8) Error!?[]const u8 {
    const Pick = struct {
        word: []const u8,
        fn matches(self: @This(), w: []const u8) bool {
            return std.mem.eql(u8, w, self.word);
        }
    };
    return remove(arena, text, number, Pick{ .word = word });
}

/// `text`, an item file with TOML front matter, without the line of `key`
/// in it; null when it has no such front matter
pub fn frontMatterRemove(arena: std.mem.Allocator, text: []const u8, key: []const u8) Error!?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var kept: std.ArrayList([]const u8) = .empty;
    var in_front = false;
    var n: usize = 0;
    while (lines.next()) |line| : (n += 1) {
        const bare = std.mem.trim(u8, line, " \t\r");
        if (n == 0) {
            if (!std.mem.eql(u8, bare, "+++")) return null;
            in_front = true;
        } else if (in_front and std.mem.eql(u8, bare, "+++")) in_front = false;
        if (in_front and n > 0) if (keyOf(bare)) |k| if (std.mem.eql(u8, k, key)) continue;
        try kept.append(arena, line);
    }
    return try std.mem.join(arena, "\n", kept.items);
}

/// `text`, an item file with TOML front matter (`+++`), with `key = value`
/// (`value` written as TOML: `"float"`, `2027-03-01`, `5`) in place of the
/// key's line, or after the ID when it has none; null when it has no such
/// front matter, or no `id` line in it
pub fn frontMatter(arena: std.mem.Allocator, text: []const u8, key: []const u8, value: []const u8) Error!?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var kept: std.ArrayList([]const u8) = .empty;
    var in_front = false;
    var id_line: ?usize = null;
    var done = false;
    var n: usize = 0;
    while (lines.next()) |line| : (n += 1) {
        const bare = std.mem.trim(u8, line, " \t\r");
        const cr = if (std.mem.endsWith(u8, line, "\r")) "\r" else "";
        if (n == 0) {
            if (!std.mem.eql(u8, bare, "+++")) return null;
            in_front = true;
        } else if (in_front and std.mem.eql(u8, bare, "+++")) in_front = false;
        if (in_front and !done and n > 0) {
            if (keyOf(bare)) |k| {
                if (std.mem.eql(u8, k, "id")) id_line = kept.items.len;
                if (std.mem.eql(u8, k, key)) {
                    try kept.append(arena, try arena.print("{s} = {s}{s}", .{ key, value, cr }));
                    done = true;
                    continue;
                }
            }
        }
        try kept.append(arena, line);
    }
    if (!done) {
        const at = id_line orelse return null;
        const cr = if (std.mem.endsWith(u8, kept.items[at], "\r")) "\r" else "";
        try kept.insert(arena, at + 1, try arena.print("{s} = {s}{s}", .{ key, value, cr }));
    }
    return try std.mem.join(arena, "\n", kept.items);
}

/// The key of a line `key = value` of TOML, without quotes
fn keyOf(line: []const u8) ?[]const u8 {
    const eq = std.mem.findScalar(u8, line, '=') orelse return null;
    const key = std.mem.trim(u8, line[0..eq], " \t");
    if (key.len == 0 or key[0] == '[' or key[0] == '#') return null;
    return std.mem.trim(u8, key, "\"");
}

const testing = std.testing;

test marker {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("# T\n%task[t.a days=2 mode=float] Text.\n", (try marker(a, "# T\n%task[t.a days=2] Text.\n", 2, "mode", "float")).?);
    try testing.expectEqualStrings("%task[t.a start=2027-03-08 days=2] Text.\n", (try marker(a, "%task[t.a start=2027-03-01 days=2] Text.\n", 1, "start", "2027-03-08")).?);
    // in bold, and a key that only begins like it
    try testing.expectEqualStrings("**%task[t.a starts=x start=1]** T.", (try marker(a, "**%task[t.a starts=x]** T.", 1, "start", "1")).?);
    try testing.expectEqual(null, try marker(a, "no marker\n", 1, "mode", "float"));
}

test markerWord {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("%task[t.a done days=2] T.", (try markerWord(a, "%task[t.a open days=2] T.", 1, "open", "done")).?);
    try testing.expectEqualStrings("%task[t.a days=2 done] T.", (try markerWord(a, "%task[t.a days=2] T.", 1, null, "done")).?);
    // the ID is not a word to replace
    try testing.expectEqualStrings("%task[open done] T.", (try markerWord(a, "%task[open] T.", 1, "open", "done")).?);
}

test "removing a key or a word" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("%task[t.a open] T.", (try markerRemove(a, "%task[t.a open days=2] T.", 1, "days")).?);
    try testing.expectEqualStrings("%task[t.a days=2] T.", (try markerRemoveWord(a, "%task[t.a open days=2] T.", 1, "open")).?);
    try testing.expectEqualStrings("%task[t.a] T.", (try markerRemove(a, "%task[t.a] T.", 1, "days")).?);
    try testing.expectEqualStrings("+++\nid = \"t.a\"\n+++\n", (try frontMatterRemove(a, "+++\nid = \"t.a\"\ndays = 2\n+++\n", "days")).?);
}

test frontMatter {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("+++\r\nid = \"t.a\"\r\nmode = \"float\"\r\ndays = 2\r\n+++\r\nText.\r\n", (try frontMatter(a, "+++\r\nid = \"t.a\"\r\ndays = 2\r\n+++\r\nText.\r\n", "mode", "\"float\"")).?);
    try testing.expectEqualStrings("+++\nid = \"t.a\"\ndays = 4\n+++\n", (try frontMatter(a, "+++\nid = \"t.a\"\ndays = 2\n+++\n", "days", "4")).?);
    try testing.expectEqual(null, try frontMatter(a, "Text.\n", "mode", "\"float\""));
}
