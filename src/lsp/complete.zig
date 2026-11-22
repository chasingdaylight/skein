//! What can be completed where the cursor is: from the text of the line
//! before it, which kind of word is being written.

const std = @import("std");

const Marker = @import("../markdown/Marker.zig");

pub const Context = union(enum) {
    /// nothing skein knows of
    none,
    /// the item type of a marker: `%ru`
    item_type: Word,
    /// the ID of an item: in a reference (`%[lex.`), or after a citation
    /// marker
    id: Word,
    /// a word of a marker after its ID: a category, a status, or a key
    word: struct { type_name: []const u8, at: Word },
    /// the value of a key of a marker: `verifies=lex.`
    value: struct { type_name: []const u8, key: []const u8, at: Word },

    /// The word being written: where it starts in the line, and what is
    /// there of it
    pub const Word = struct { start: usize, text: []const u8 };
};

/// What is being written at the end of `before`, the text of a line up
/// to the cursor
pub fn context(before: []const u8) Context {
    const percent = std.mem.findScalarLast(u8, before, '%') orelse return .none;
    const rest = before[percent + 1 ..];
    const open = std.mem.findScalar(u8, rest, '[') orelse {
        // a marker's type, where a marker can start
        for (rest) |c| {
            if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '-' and c != '_') return .none;
        }
        if (!atStart(before[0..percent])) return .none;
        return .{ .item_type = .{ .start = percent + 1, .text = rest } };
    };
    const name = rest[0..open];
    const inner = rest[open + 1 ..];
    const inner_start = percent + 1 + open + 1;
    if (std.mem.findScalar(u8, inner, ']') != null) return .none;
    // inside quotes, a value is being written by hand
    if (std.mem.count(u8, inner, "\"") % 2 == 1) return .none;

    const space = std.mem.findScalarLast(u8, inner, ' ');
    if (name.len == 0) {
        // a reference: its ID; what follows a space is the words to show
        if (space != null) return .none;
        return .{ .id = .{ .start = inner_start, .text = inner } };
    }
    // a marker: its first word is a new ID, which nothing can complete
    const word_start = (space orelse return .none) + 1;
    const word = inner[word_start..];
    if (std.mem.findScalar(u8, word, '=')) |eq| {
        const value = word[eq + 1 ..];
        const last = if (std.mem.findScalarLast(u8, value, ',')) |comma| comma + 1 else 0;
        return .{ .value = .{
            .type_name = name,
            .key = word[0..eq],
            .at = .{ .start = inner_start + word_start + eq + 1 + last, .text = value[last..] },
        } };
    }
    return .{ .word = .{ .type_name = name, .at = .{ .start = inner_start + word_start, .text = word } } };
}

/// The ID being written after a citation marker (`// spec:`), when
/// `before` has one
pub fn citation(before: []const u8, marker: []const u8) ?Context.Word {
    const at = std.mem.findLast(u8, before, marker) orelse return null;
    const after = before[at + marker.len ..];
    var start = after.len;
    while (start > 0 and isIdChar(after[start - 1])) start -= 1;
    // a full stop followed by a space ended the IDs
    if (std.mem.find(u8, after[0..start], ". ") != null) return null;
    return .{ .start = at + marker.len + start, .text = after[start..] };
}

fn isIdChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '-' or c == ':';
}

/// Whether a marker can start after `text`: the indentation and the
/// bullets or numbers of list entries
fn atStart(text: []const u8) bool {
    for (text) |c| {
        if (std.mem.findScalar(u8, " \t-*+.)0123456789", c) == null) return false;
    }
    return true;
}

test {
    _ = Marker;
}

const testing = std.testing;

test "a marker's type, where a marker can start" {
    const c = context("- %ru");
    try testing.expectEqualStrings("ru", c.item_type.text);
    try testing.expectEqual(3, c.item_type.start);
    try testing.expectEqualStrings("", context("%").item_type.text);
    try testing.expectEqual(.none, context("a rise of 50%"));
    try testing.expectEqual(.none, context("text %ru"));
}

test "the ID of a reference" {
    const c = context("See %[lex.to");
    try testing.expectEqualStrings("lex.to", c.id.text);
    try testing.expectEqual(6, c.id.start);
    try testing.expectEqualStrings("", context("See %[").id.text);
    // the words to show, and a reference that is closed
    try testing.expectEqual(.none, context("See %[lex.token the to"));
    try testing.expectEqual(.none, context("See %[lex.token] and"));
}

test "the words and values of a marker" {
    // the new ID is the author's to choose
    try testing.expectEqual(.none, context("%rule[lex.com"));
    const word = context("%rule[lex.comment syn");
    try testing.expectEqualStrings("rule", word.word.type_name);
    try testing.expectEqualStrings("syn", word.word.at.text);
    try testing.expectEqual(18, word.word.at.start);
    try testing.expectEqualStrings("", context("%rule[lex.comment syntax ").word.at.text);

    const value = context("%case[c.one verifies=lex.a,lex.");
    try testing.expectEqualStrings("case", value.value.type_name);
    try testing.expectEqualStrings("verifies", value.value.key);
    try testing.expectEqualStrings("lex.", value.value.at.text);
    try testing.expectEqual(27, value.value.at.start);
    try testing.expectEqualStrings("", context("%rule[a.b status=").value.at.text);
    try testing.expectEqual(.none, context("%rule[a.b note=\"two wo"));
    try testing.expectEqual(.none, context("%rule[a.b syntax] Text"));
}

test "the ID after a citation marker" {
    const c = citation("    // spec: lex.token, lex.co", "// spec:").?;
    try testing.expectEqualStrings("lex.co", c.text);
    try testing.expectEqual(24, c.start);
    try testing.expectEqualStrings("", citation("// spec: ", "// spec:").?.text);
    try testing.expectEqual(null, citation("// spec: lex.token. And pro", "// spec:"));
    try testing.expectEqual(null, citation("const x = 1;", "// spec:"));
}
