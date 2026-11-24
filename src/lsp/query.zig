//! What the cursor is on: the ID of an item, in a marker, a reference, a
//! link, a citation or plain text.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Marker = @import("../markdown/Marker.zig");

pub fn isIdChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '-' or c == ':';
}

/// The line `number` (0-based) of `text`, without its line end
pub fn lineOf(text: []const u8, number: usize) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: usize = 0;
    while (lines.next()) |line| : (n += 1) {
        if (n == number) return std.mem.trimEnd(u8, line, "\r");
    }
    return null;
}

/// The word of ID characters that the column `character` of `line` is in
/// or just after, without a full stop or hyphen at its end
pub fn wordAt(line: []const u8, character: usize) ?[]const u8 {
    var at = @min(character, line.len);
    if ((at == line.len or !isIdChar(line[at])) and at > 0 and isIdChar(line[at - 1])) at -= 1;
    if (at >= line.len or !isIdChar(line[at])) return null;
    var start = at;
    while (start > 0 and isIdChar(line[start - 1])) start -= 1;
    var end = at;
    while (end < line.len and isIdChar(line[end])) end += 1;
    const word = std.mem.trimEnd(u8, line[start..end], ".-:");
    return if (word.len == 0) null else word;
}

/// The item the cursor is on, in the file `file` (a path from the
/// project's root): the one whose ID the word under the cursor is, or,
/// on a marker whose ID starts with a dot, the part that marker declares
pub fn itemAt(graph: *const Graph, file: []const u8, text: []const u8, position: struct { line: usize, character: usize }) ?*const Item {
    const line = lineOf(text, position.line) orelse return null;
    const word = wordAt(line, position.character) orelse return declaredAt(graph, file, line, position.line);
    if (graph.find(word)) |item| return item;
    return declaredAt(graph, file, line, position.line);
}

/// The item that the marker of this line declares
fn declaredAt(graph: *const Graph, file: []const u8, line: []const u8, number: usize) ?*const Item {
    if (Marker.startIn(line) == null) return null;
    for (graph.items) |*item| {
        if (item.in_document and item.line == number + 1 and std.mem.eql(u8, item.file, file)) return item;
    }
    return null;
}

const testing = std.testing;

test wordAt {
    const line = "See %[lex.token the token], and lex.other.";
    try testing.expectEqualStrings("lex.token", wordAt(line, 6).?);
    try testing.expectEqualStrings("lex.token", wordAt(line, 14).?);
    try testing.expectEqualStrings("lex.token", wordAt(line, 15).?);
    try testing.expectEqualStrings("the", wordAt(line, 17).?);
    try testing.expectEqualStrings("lex.other", wordAt(line, 41).?);
    try testing.expectEqualStrings("lex.other", wordAt(line, 99).?);
    try testing.expectEqual(null, wordAt("a  b", 2));
    try testing.expectEqual(null, wordAt("", 0));
}

test lineOf {
    try testing.expectEqualStrings("two", lineOf("one\r\ntwo\r\nthree", 1).?);
    try testing.expectEqualStrings("", lineOf("one\n", 1).?);
    try testing.expectEqual(null, lineOf("one", 3));
}
