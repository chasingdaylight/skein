//! Renaming IDs in text: on a line, every whole ID that is to be renamed
//! is replaced by its new name. An ID inside a longer one is left alone
//! (`lex.token` in `lex.token.kinds`), and so is an ID of another
//! repository (`other:lex.token`).

const std = @import("std");

/// old ID to new ID
pub const Renames = std.array_hash_map.String([]const u8);

pub const Result = struct {
    text: []const u8,
    /// how many IDs were replaced
    count: usize,
};

/// What an ID, or a reference to one, can be made of
fn isIdChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '-' or c == ':';
}

/// `text` with every ID of `renames` in it replaced. A full stop or a
/// hyphen at the end of a word is not part of the ID before it.
pub fn line(arena: std.mem.Allocator, text: []const u8, renames: *const Renames) std.mem.Allocator.Error!Result {
    var out: std.ArrayList(u8) = .empty;
    var count: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (!isIdChar(text[i])) {
            try out.append(arena, text[i]);
            i += 1;
            continue;
        }
        var end = i;
        while (end < text.len and isIdChar(text[end])) end += 1;
        const word = text[i..end];
        const id = std.mem.trimEnd(u8, word, ".-:");
        if (renames.get(id)) |new| {
            try out.appendSlice(arena, new);
            try out.appendSlice(arena, word[id.len..]);
            count += 1;
        } else try out.appendSlice(arena, word);
        i = end;
    }
    return .{ .text = out.items, .count = count };
}

// req: move.everywhere
const testing = std.testing;

fn expectLine(expected: []const u8, text: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var renames: Renames = .empty;
    try renames.put(a, "lex.token", "lex.lexeme");
    try renames.put(a, "lex.token.kinds", "lex.lexeme.kinds");
    try renames.put(a, "SRS-001", "SRS-100");
    try testing.expectEqualStrings(expected, (try line(a, text, &renames)).text);
}

test "whole IDs are renamed, wherever they stand" {
    try expectLine("%rule[lex.lexeme syntax] A lexeme.", "%rule[lex.token syntax] A lexeme.");
    try expectLine("See %[lex.lexeme the token] and %[lex.lexeme.kinds].", "See %[lex.token the token] and %[lex.token.kinds].");
    try expectLine("%case[c.one verifies=lex.lexeme,lex.other see=SRS-100]", "%case[c.one verifies=lex.token,lex.other see=SRS-001]");
    try expectLine("// spec: lex.lexeme, lex.lexeme.kinds. And prose.", "// spec: lex.token, lex.token.kinds. And prose.");
    try expectLine("refines = [\"SRS-100\", \"SRS-002\"]", "refines = [\"SRS-001\", \"SRS-002\"]");
    try expectLine("id = \"SRS-100\"\r", "id = \"SRS-001\"\r");
}

test "an ID inside another, or of another repository, is not" {
    try expectLine("%[lex.token.other] and %[lex.tokens] and %[x.lex.token]", "%[lex.token.other] and %[lex.tokens] and %[x.lex.token]");
    try expectLine("%[other:lex.token] and SRS-0012 and %rule[.token]", "%[other:lex.token] and SRS-0012 and %rule[.token]");
}

test "the count says how many were replaced" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var renames: Renames = .empty;
    try renames.put(a, "a.b", "a.c");
    try testing.expectEqual(2, (try line(a, "%[a.b] and a.b, not a.bc", &renames)).count);
    try testing.expectEqual(0, (try line(a, "nothing here", &renames)).count);
}
