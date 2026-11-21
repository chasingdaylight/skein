//! The marker that makes a paragraph or a list entry an item:
//!
//!     %rule[lex.comment.line legality final stage=s0 verifies=lex.token,lex.space]
//!
//! A percent sign, the item type, and in brackets the ID and then words:
//! a bare word is the category or the status (whichever of the type's it
//! is), and `key=value` an attribute or links (values separated by commas,
//! or one value in double quotes). The item's text follows on the same
//! line or starts on the next.
//!
//! An ID that starts with a dot is a part's name within its whole:
//! `%rule[.as]` inside `lex.keywords` is `lex.keywords.as`.

const std = @import("std");

const Marker = @This();

type_name: []const u8,
id: []const u8,
/// the words without `=`, in order
words: []const []const u8 = &.{},
fields: []const Field = &.{},
/// how much of the line the marker takes, the closing bracket included
len: usize,
/// what is wrong with the marker, if anything
problem: ?[]const u8 = null,

pub const Field = struct {
    key: []const u8,
    values: []const []const u8,
};

/// Whether `line` starts as a marker does: `%`, a name, `[`
pub fn startsOne(line: []const u8) bool {
    if (line.len < 3 or line[0] != '%' or !std.ascii.isLower(line[1])) return false;
    var i: usize = 1;
    while (i < line.len and (std.ascii.isLower(line[i]) or std.ascii.isDigit(line[i]) or line[i] == '-' or line[i] == '_')) i += 1;
    return i < line.len and line[i] == '[';
}

/// How much of `line`, which starts a marker, the marker takes: up to its
/// closing bracket, or all of it when it has none
pub fn extent(line: []const u8) usize {
    const open = std.mem.findScalar(u8, line, '[') orelse return line.len;
    return if (closingBracket(line, open)) |close| close + 1 else line.len;
}

/// The marker that `line` starts with; null when it starts with none.
/// A marker with a mistake in it is still a marker, with its `problem`.
pub fn parse(arena: std.mem.Allocator, line: []const u8) std.mem.Allocator.Error!?Marker {
    if (!startsOne(line)) return null;
    const open = std.mem.findScalar(u8, line, '[').?;
    var out: Marker = .{ .type_name = line[1..open], .id = "", .len = line.len };
    const close = closingBracket(line, open) orelse {
        out.problem = "the marker is not closed by ']'";
        return out;
    };
    out.len = close + 1;
    const inside = line[open + 1 .. close];

    var words: std.ArrayList([]const u8) = .empty;
    var fields: std.ArrayList(Field) = .empty;
    var at: usize = 0;
    var first = true;
    while (true) {
        while (at < inside.len and (inside[at] == ' ' or inside[at] == '\t')) at += 1;
        if (at == inside.len) break;
        const start = at;
        while (at < inside.len and inside[at] != ' ' and inside[at] != '\t' and inside[at] != '=') at += 1;
        const word = inside[start..at];
        if (first) {
            first = false;
            if (at < inside.len and inside[at] == '=') {
                out.problem = "the ID comes first in the brackets";
                break;
            }
            if (!validId(word)) {
                out.id = word;
                out.problem = "an ID is letters, digits, '.', '-' and '_'";
                break;
            }
            out.id = word;
            continue;
        }
        if (at == inside.len or inside[at] != '=') {
            try words.append(arena, word);
            continue;
        }
        at += 1;
        if (word.len == 0) {
            out.problem = "'=' needs a key before it";
            break;
        }
        var values: std.ArrayList([]const u8) = .empty;
        if (at < inside.len and inside[at] == '"') {
            const end = std.mem.findScalarPos(u8, inside, at + 1, '"') orelse {
                out.problem = "the quoted value is not closed";
                break;
            };
            try values.append(arena, inside[at + 1 .. end]);
            at = end + 1;
        } else {
            const from = at;
            while (at < inside.len and inside[at] != ' ' and inside[at] != '\t') at += 1;
            var parts = std.mem.splitScalar(u8, inside[from..at], ',');
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
    if (out.id.len == 0 and out.problem == null) out.problem = "the brackets hold no ID";
    out.words = words.items;
    out.fields = fields.items;
    return out;
}

/// Where the bracket opened at `open` closes; a `]` inside double quotes
/// does not close it
fn closingBracket(line: []const u8, open: usize) ?usize {
    var quoted = false;
    for (line[open + 1 ..], open + 1..) |c, i| {
        if (c == '"') quoted = !quoted;
        if (c == ']' and !quoted) return i;
    }
    return null;
}

fn validId(id: []const u8) bool {
    if (id.len == 0 or std.mem.eql(u8, id, ".")) return false;
    for (id) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '_') return false;
    }
    return true;
}

// req: items.marker, items.marker.words, items.marker.mistakes
const testing = std.testing;

test "a marker with only an ID, and the text after it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const line = "%rule[lex.comment.line] A line comment starts with two slashes.";
    const m = (try parse(arena.allocator(), line)).?;
    try testing.expectEqualStrings("rule", m.type_name);
    try testing.expectEqualStrings("lex.comment.line", m.id);
    try testing.expectEqual(0, m.words.len);
    try testing.expectEqual(0, m.fields.len);
    try testing.expectEqual(null, m.problem);
    try testing.expectEqualStrings(" A line comment starts with two slashes.", line[m.len..]);
}

test "a marker with words, attributes and links" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const m = (try parse(arena.allocator(), "%rule[expr.as.narrow legality  final stage=s0 verifies=a.b,c.d note=\"two words, and a ]\"]")).?;
    try testing.expectEqualStrings("expr.as.narrow", m.id);
    try testing.expectEqual(2, m.words.len);
    try testing.expectEqualStrings("legality", m.words[0]);
    try testing.expectEqualStrings("final", m.words[1]);
    try testing.expectEqual(3, m.fields.len);
    try testing.expectEqualStrings("stage", m.fields[0].key);
    try testing.expectEqualStrings("s0", m.fields[0].values[0]);
    try testing.expectEqual(2, m.fields[1].values.len);
    try testing.expectEqualStrings("c.d", m.fields[1].values[1]);
    try testing.expectEqualStrings("two words, and a ]", m.fields[2].values[0]);
    try testing.expectEqual(null, m.problem);
}

test "a part's name starts with a dot" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const m = (try parse(arena.allocator(), "%rule[.as final] `as`")).?;
    try testing.expectEqualStrings(".as", m.id);
    try testing.expectEqual(null, m.problem);
}

test "lines that do not start a marker" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "rule[a.b] without the percent sign",
        "array[i] is the element",
        "% rule[a.b]",
        "%rule [a.b]",
        "%Rule[a.b]",
        "%[a.b]",
        "100%rule[a.b]",
        "50% of the time",
        "",
    }) |line| try testing.expectEqual(null, try parse(arena.allocator(), line));
}

test "markers with mistakes are markers still" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "%rule[a.b",
        "%rule[]",
        "%rule[a/b]",
        "%rule[.]",
        "%rule[stage=s0]",
        "%rule[a.b =x]",
        "%rule[a.b key=]",
        "%rule[a.b key=a,,b]",
        "%rule[a.b key=\"open]",
    }) |line| {
        const m = (try parse(arena.allocator(), line)).?;
        testing.expect(m.problem != null) catch |e| {
            std.debug.print("no problem found in: {s}\n", .{line});
            return e;
        };
    }
}
