//! Quick fixes: a problem of skein's that names what would mend it (a
//! former ID to write as the item's ID now, or a misspelled word with
//! the one meant) is mended by writing that word in place of the other,
//! on the problem's line or, in the item's front matter, on one of the
//! lines after it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Marker = @import("../markdown/Marker.zig");
const Server = @import("Server.zig");
const protocol = @import("protocol.zig");
const query = @import("query.zig");

/// How far after its line a problem's word is looked for
const lines_after = 200;

pub fn codeAction(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    const uri = Server.field(Server.field(params, "textDocument"), "uri");
    const diagnostics = Server.field(Server.field(params, "context"), "diagnostics");
    if (uri != .string or diagnostics != .array) return s.respond(a, id, null);
    var ws = s.open(a) orelse return s.respond(a, id, null);
    defer ws.close();
    const file = try s.fileOf(a, &ws, uri.string) orelse return s.respond(a, id, null);
    const text = s.textOf(a, &ws, uri.string, file) orelse return s.respond(a, id, null);

    var out: std.ArrayList(protocol.CodeAction) = .empty;
    for (diagnostics.array.items) |d| {
        const fix = Server.parse(protocol.Fix, a, Server.field(d, "data")) orelse continue;
        const line = Server.parse(protocol.Range, a, Server.field(d, "range")) orelse continue;
        const range = find(text, line.start.line, fix.old) orelse continue;
        var changes: json.ArrayHashMap([]const protocol.TextEdit) = .{};
        try changes.map.put(a, uri.string, try a.dupe(protocol.TextEdit, &.{.{ .range = range, .newText = fix.new }}));
        try out.append(a, .{
            .title = try a.print("Write '{s}' for '{s}'", .{ fix.new, fix.old }),
            .diagnostics = try a.dupe(json.Value, &.{d}),
            .edit = .{ .changes = changes },
        });
    }
    try s.respond(a, id, out.items);
}

/// Where `word` stands as a whole word: on the line `from` (0-based), else
/// on the lines after it up to the next marker
pub fn find(text: []const u8, from: usize, word: []const u8) ?protocol.Range {
    var n = from;
    while (n <= from + lines_after) : (n += 1) {
        const line = query.lineOf(text, n) orelse return null;
        if (n > from and Marker.startIn(line) != null) return null;
        if (wholeWord(line, word)) |at| return .{ .start = .{ .line = n, .character = at }, .end = .{ .line = n, .character = at + word.len } };
    }
    return null;
}

/// Where `word` is in `line` with no ID character just before or after it
fn wholeWord(line: []const u8, word: []const u8) ?usize {
    var from: usize = 0;
    while (std.mem.findPos(u8, line, from, word)) |at| : (from = at + 1) {
        const before_ok = at == 0 or !query.isIdChar(line[at - 1]);
        const end = at + word.len;
        // a full stop may end a sentence after an ID
        const after_ok = end == line.len or !query.isIdChar(line[end]) or (line[end] == '.' and (end + 1 == line.len or !query.isIdChar(line[end + 1])));
        if (before_ok and after_ok) return at;
    }
    return null;
}

// cspell:ignore syntx tokne drfat
const testing = std.testing;

test find {
    const text = "%rule[lex.a syntx]\nsee %[lex.tokne].\n+++\nstatus = \"drfat\"\n";
    try testing.expectEqual(12, find(text, 0, "syntx").?.start.character);
    try testing.expectEqual(1, find(text, 1, "lex.tokne").?.start.line);
    // in front matter, lines after the problem's
    try testing.expectEqual(3, find(text, 2, "drfat").?.start.line);
    // a word inside another is not it
    try testing.expectEqual(null, find("lex.abc", 0, "lex.ab"));
    // nor past the next marker
    try testing.expectEqual(null, find("one\n%rule[x] two", 0, "two"));
}
