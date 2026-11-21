//! Reads CSV (RFC 4180): quoted fields may hold the delimiter, line ends
//! and doubled quotes. The delimiter is a comma, or a semicolon when the
//! first line has more of those, as spreadsheets in some locales write.

const std = @import("std");

pub const Error = error{
    /// a quoted field is not closed
    UnclosedQuote,
} || std.mem.Allocator.Error;

/// The rows of `text`, each a list of fields. Empty lines are left out,
/// and a byte order mark at the start is passed over.
pub fn parse(arena: std.mem.Allocator, text: []const u8) Error![]const []const []const u8 {
    const bom = "\xEF\xBB\xBF";
    const src = if (std.mem.startsWith(u8, text, bom)) text[bom.len..] else text;
    const delimiter = delimiterOf(src);

    var rows: std.ArrayList([]const []const u8) = .empty;
    var row: std.ArrayList([]const u8) = .empty;
    var field: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    var quoted = false; // inside quotes
    var was_quoted = false; // the field had quotes: it is a field even when empty
    while (i < src.len) : (i += 1) {
        const c = src[i];
        if (quoted) {
            if (c != '"') {
                if (c != '\r') try field.append(arena, c);
            } else if (i + 1 < src.len and src[i + 1] == '"') {
                try field.append(arena, '"');
                i += 1;
            } else quoted = false;
            continue;
        }
        if (c == '"' and field.items.len == 0) {
            quoted = true;
            was_quoted = true;
        } else if (c == delimiter) {
            try row.append(arena, try arena.dupe(u8, field.items));
            field.clearRetainingCapacity();
            was_quoted = false;
        } else if (c == '\n') {
            try endRow(arena, &rows, &row, &field, was_quoted);
            was_quoted = false;
        } else if (c != '\r') {
            try field.append(arena, c);
        }
    }
    if (quoted) return error.UnclosedQuote;
    try endRow(arena, &rows, &row, &field, was_quoted);
    return rows.items;
}

fn endRow(
    arena: std.mem.Allocator,
    rows: *std.ArrayList([]const []const u8),
    row: *std.ArrayList([]const u8),
    field: *std.ArrayList(u8),
    was_quoted: bool,
) !void {
    // a line with nothing on it is no row
    if (row.items.len == 0 and field.items.len == 0 and !was_quoted) return;
    try row.append(arena, try arena.dupe(u8, field.items));
    field.clearRetainingCapacity();
    try rows.append(arena, try arena.dupe([]const u8, row.items));
    row.clearRetainingCapacity();
}

fn delimiterOf(src: []const u8) u8 {
    const first = src[0 .. std.mem.findScalar(u8, src, '\n') orelse src.len];
    return if (std.mem.count(u8, first, ";") > std.mem.count(u8, first, ",")) ';' else ',';
}

const testing = std.testing;

test "fields: plain, quoted, with delimiters, quotes and line ends inside" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const rows = try parse(arena.allocator(), "\xEF\xBB\xBFid,text,note\r\n" ++
        "SWE-013,\"The project shall, at least, say \"\"hello\"\".\nOn two lines.\",\r\n" ++
        "\r\n" ++
        "SWE-014,plain,\"\"\n" ++
        "SWE-015,last line without an end");
    try testing.expectEqual(4, rows.len);
    try testing.expectEqualStrings("note", rows[0][2]);
    try testing.expectEqualStrings("The project shall, at least, say \"hello\".\nOn two lines.", rows[1][1]);
    try testing.expectEqualStrings("", rows[1][2]);
    try testing.expectEqual(3, rows[2].len);
    try testing.expectEqualStrings("", rows[2][2]);
    try testing.expectEqual(2, rows[3].len);
    try testing.expectEqualStrings("last line without an end", rows[3][1]);
}

test "semicolons, when the first line has more of them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const rows = try parse(arena.allocator(), "id;text;note\nA-1;one, with a comma;x\n");
    try testing.expectEqual(3, rows[0].len);
    try testing.expectEqualStrings("one, with a comma", rows[1][1]);
}

test "a quote that is never closed, and no rows at all" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.UnclosedQuote, parse(arena.allocator(), "id,text\nA-1,\"open\n"));
    try testing.expectEqual(0, (try parse(arena.allocator(), "\n\r\n")).len);
}
