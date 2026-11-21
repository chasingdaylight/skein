//! The line that makes the block after it an item:
//!
//!     rule[lex.comment.line] legality stage=s0 verifies=lex.token,lex.space
//!
//! The item type, the ID in brackets, then words: a bare word is the
//! category, `key=value` an attribute, the status or links (values
//! separated by commas, or one value in double quotes).

const std = @import("std");

const Marker = @This();

type_name: []const u8,
id: []const u8,
category: ?[]const u8 = null,
fields: []const Field = &.{},
/// what is wrong with the words after the ID, if anything
problem: ?[]const u8 = null,

pub const Field = struct {
    key: []const u8,
    values: []const []const u8,
};

/// The marker that `line` is; null when it is not one. A line is a marker
/// only when it starts with one of `types` and a bracketed ID, so prose
/// such as `array[i] is the element` is left alone.
pub fn parse(arena: std.mem.Allocator, line: []const u8, types: []const []const u8) std.mem.Allocator.Error!?Marker {
    const open = std.mem.findScalar(u8, line, '[') orelse return null;
    const type_name = line[0..open];
    const known = for (types) |t| {
        if (std.mem.eql(u8, t, type_name)) break true;
    } else false;
    if (!known) return null;
    const close = std.mem.findScalarPos(u8, line, open, ']') orelse return null;
    const id = line[open + 1 .. close];
    if (id.len == 0) return null;
    for (id) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '_') return null;
    }
    const rest = line[close + 1 ..];
    if (rest.len > 0 and rest[0] != ' ' and rest[0] != '\t') return null;

    var out: Marker = .{ .type_name = type_name, .id = id };
    var fields: std.ArrayList(Field) = .empty;
    var at: usize = 0;
    while (true) {
        while (at < rest.len and (rest[at] == ' ' or rest[at] == '\t')) at += 1;
        if (at == rest.len) break;
        const start = at;
        while (at < rest.len and rest[at] != ' ' and rest[at] != '\t' and rest[at] != '=') at += 1;
        const word = rest[start..at];
        if (at == rest.len or rest[at] != '=') {
            // a bare word: the category
            if (word.len == 0 or out.category != null) {
                out.problem = "expected one category and key=value words after the ID";
                break;
            }
            out.category = word;
            continue;
        }
        at += 1;
        if (word.len == 0) {
            out.problem = "'=' needs a key before it";
            break;
        }
        var values: std.ArrayList([]const u8) = .empty;
        if (at < rest.len and rest[at] == '"') {
            const end = std.mem.findScalarPos(u8, rest, at + 1, '"') orelse {
                out.problem = "the quoted value is not closed";
                break;
            };
            try values.append(arena, rest[at + 1 .. end]);
            at = end + 1;
        } else {
            const from = at;
            while (at < rest.len and rest[at] != ' ' and rest[at] != '\t') at += 1;
            var parts = std.mem.splitScalar(u8, rest[from..at], ',');
            while (parts.next()) |part| {
                if (part.len == 0) {
                    out.problem = "a value is missing after '=' or a comma";
                    break;
                }
                try values.append(arena, part);
            }
            if (out.problem != null) break;
        }
        try fields.append(arena, .{ .key = word, .values = values.items });
    }
    out.fields = fields.items;
    return out;
}

// req: items.marker, items.marker.types-only, items.marker.words
const testing = std.testing;
const test_types = [_][]const u8{ "rule", "term" };

fn parseTest(arena: *std.heap.ArenaAllocator, line: []const u8) !?Marker {
    return parse(arena.allocator(), line, &test_types);
}

test "a marker with only an ID" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const m = (try parseTest(&arena, "rule[lex.comment.line]")).?;
    try testing.expectEqualStrings("rule", m.type_name);
    try testing.expectEqualStrings("lex.comment.line", m.id);
    try testing.expectEqual(null, m.category);
    try testing.expectEqual(0, m.fields.len);
    try testing.expectEqual(null, m.problem);
}

test "a marker with a category, attributes and links" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const m = (try parseTest(&arena, "rule[expr.as.narrow] legality  stage=s0 verifies=a.b,c.d note=\"two words\"")).?;
    try testing.expectEqualStrings("legality", m.category.?);
    try testing.expectEqual(3, m.fields.len);
    try testing.expectEqualStrings("stage", m.fields[0].key);
    try testing.expectEqualStrings("s0", m.fields[0].values[0]);
    try testing.expectEqual(2, m.fields[1].values.len);
    try testing.expectEqualStrings("c.d", m.fields[1].values[1]);
    try testing.expectEqualStrings("two words", m.fields[2].values[0]);
    try testing.expectEqual(null, m.problem);
}

test "lines that are not markers" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "array[i] is the element",
        "rule",
        "rule[]",
        "rule[a b]",
        "rule[a.b]c",
        " rule[a.b]",
        "rule [a.b]",
        "rule[a.b",
        "[rule]",
    }) |line| try testing.expectEqual(null, try parseTest(&arena, line));
}

test "markers with mistakes after the ID" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "rule[a.b] one two",
        "rule[a.b] =x",
        "rule[a.b] key=",
        "rule[a.b] key=a,,b",
        "rule[a.b] key=\"open",
    }) |line| try testing.expect((try parseTest(&arena, line)).?.problem != null);
}
