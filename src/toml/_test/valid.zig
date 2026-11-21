//! Documents the parser must accept, after the examples of the TOML
//! specification (toml.io, v1.0.0 and v1.1.0).

// req: project.toml
const std = @import("std");
const testing = std.testing;

const toml = @import("../../toml.zig");

const Doc = struct {
    arena: std.heap.ArenaAllocator,
    root: *toml.Table,

    fn deinit(self: *Doc) void {
        self.arena.deinit();
    }

    /// The value at a path of keys from the root
    fn at(self: *const Doc, path: []const []const u8) toml.Value {
        var v: toml.Value = .{ .table = self.root };
        for (path) |key| v = v.table.get(key) orelse std.debug.panic("no key '{s}'", .{key});
        return v;
    }
};

fn parse(source: []const u8) !Doc {
    var doc: Doc = .{ .arena = .init(testing.allocator), .root = undefined };
    errdefer doc.arena.deinit();
    var diag: toml.Diagnostic = .{};
    doc.root = toml.parse(doc.arena.allocator(), source, &diag) catch |e| {
        std.debug.print("{d}:{d}: {s}\n", .{ diag.line, diag.column, diag.message });
        return e;
    };
    return doc;
}

test "an empty document, comments and blank lines" {
    var doc = try parse("# only a comment\n\n   \n# another\r\n");
    defer doc.deinit();
    try testing.expectEqual(0, doc.root.keys().len);
}

test "keys: bare, quoted, dotted, in the order written" {
    var doc = try parse(
        \\bare-key_1 = 1
        \\"quoted key" = 2
        \\'literal.key' = 3
        \\1234 = 4
        \\fruit . apple . color = "red"
        \\fruit.apple.smooth = true
        \\"" = 5
    );
    defer doc.deinit();
    try testing.expectEqual(1, doc.at(&.{"bare-key_1"}).integer);
    try testing.expectEqual(2, doc.at(&.{"quoted key"}).integer);
    try testing.expectEqual(3, doc.at(&.{"literal.key"}).integer);
    try testing.expectEqual(4, doc.at(&.{"1234"}).integer);
    try testing.expectEqualStrings("red", doc.at(&.{ "fruit", "apple", "color" }).string);
    try testing.expect(doc.at(&.{ "fruit", "apple", "smooth" }).boolean);
    try testing.expectEqual(5, doc.at(&.{""}).integer);
    try testing.expectEqualStrings("bare-key_1", doc.root.keys()[0]);
    try testing.expectEqualStrings("fruit", doc.root.keys()[4]);
}

test "basic strings and their escapes" {
    var doc = try parse(
        \\a = "tab\there, quote \" and backslash \\"
        \\b = "\u00E9\U0001F600\x41\e"
        \\c = ""
    );
    defer doc.deinit();
    try testing.expectEqualStrings("tab\there, quote \" and backslash \\", doc.at(&.{"a"}).string);
    try testing.expectEqualStrings("\u{e9}\u{1F600}A\x1b", doc.at(&.{"b"}).string);
    try testing.expectEqualStrings("", doc.at(&.{"c"}).string);
}

test "literal strings keep backslashes" {
    var doc = try parse("path = 'C:\\Users\\nodejs'\nregex = '<\\i\\c*\\s*>'\n");
    defer doc.deinit();
    try testing.expectEqualStrings("C:\\Users\\nodejs", doc.at(&.{"path"}).string);
    try testing.expectEqualStrings("<\\i\\c*\\s*>", doc.at(&.{"regex"}).string);
}

test "multi-line strings" {
    var doc = try parse("a = \"\"\"\nRoses are red\r\nViolets are blue\"\"\"\n" ++
        "b = \"\"\"\\\n   The quick brown \\\n\n   fox.\\\n   \"\"\"\n" ++
        "c = \"\"\"two \"\" quotes, and one at the end\"\"\"\"\n" ++
        "d = '''\nraw \\n text\n'''\n" ++
        "e = '''that's ''two'' and done'''''\n");
    defer doc.deinit();
    try testing.expectEqualStrings("Roses are red\nViolets are blue", doc.at(&.{"a"}).string);
    try testing.expectEqualStrings("The quick brown fox.", doc.at(&.{"b"}).string);
    try testing.expectEqualStrings("two \"\" quotes, and one at the end\"", doc.at(&.{"c"}).string);
    try testing.expectEqualStrings("raw \\n text\n", doc.at(&.{"d"}).string);
    try testing.expectEqualStrings("that's ''two'' and done''", doc.at(&.{"e"}).string);
}

test "integers" {
    var doc = try parse(
        \\a = +99
        \\b = -17
        \\c = 0
        \\d = 1_000_000
        \\e = 0xDEAD_beef
        \\f = 0o755
        \\g = 0b1101
        \\h = -9223372036854775808
    );
    defer doc.deinit();
    try testing.expectEqual(99, doc.at(&.{"a"}).integer);
    try testing.expectEqual(-17, doc.at(&.{"b"}).integer);
    try testing.expectEqual(0, doc.at(&.{"c"}).integer);
    try testing.expectEqual(1_000_000, doc.at(&.{"d"}).integer);
    try testing.expectEqual(0xdeadbeef, doc.at(&.{"e"}).integer);
    try testing.expectEqual(0o755, doc.at(&.{"f"}).integer);
    try testing.expectEqual(13, doc.at(&.{"g"}).integer);
    try testing.expectEqual(std.math.minInt(i64), doc.at(&.{"h"}).integer);
}

test "floats" {
    var doc = try parse(
        \\a = +1.0
        \\b = -0.01
        \\c = 5e+22
        \\d = 6.626e-34
        \\e = 9_224.5
        \\f = inf
        \\g = -inf
        \\h = nan
        \\i = 1E6
    );
    defer doc.deinit();
    try testing.expectEqual(1.0, doc.at(&.{"a"}).float);
    try testing.expectEqual(-0.01, doc.at(&.{"b"}).float);
    try testing.expectEqual(5e22, doc.at(&.{"c"}).float);
    try testing.expectEqual(6.626e-34, doc.at(&.{"d"}).float);
    try testing.expectEqual(9224.5, doc.at(&.{"e"}).float);
    try testing.expect(std.math.isPositiveInf(doc.at(&.{"f"}).float));
    try testing.expect(std.math.isNegativeInf(doc.at(&.{"g"}).float));
    try testing.expect(std.math.isNan(doc.at(&.{"h"}).float));
    try testing.expectEqual(1e6, doc.at(&.{"i"}).float);
}

test "dates and times" {
    var doc = try parse(
        \\a = 1979-05-27T07:32:00Z
        \\b = 1979-05-27T00:32:00.999999-07:00
        \\c = 1979-05-27 07:32:00
        \\d = 2024-02-29
        \\e = 07:32:00.5
        \\f = 13:37
    );
    defer doc.deinit();
    const a = doc.at(&.{"a"}).datetime;
    try testing.expectEqual(toml.Date{ .year = 1979, .month = 5, .day = 27 }, a.date.?);
    try testing.expectEqual(toml.Time{ .hour = 7, .minute = 32 }, a.time.?);
    try testing.expectEqual(0, a.offset_minutes.?);
    const b = doc.at(&.{"b"}).datetime;
    try testing.expectEqual(999_999_000, b.time.?.nanosecond);
    try testing.expectEqual(-420, b.offset_minutes.?);
    const c = doc.at(&.{"c"}).datetime;
    try testing.expectEqual(32, c.time.?.minute);
    try testing.expectEqual(null, c.offset_minutes);
    const d = doc.at(&.{"d"}).datetime;
    try testing.expectEqual(29, d.date.?.day);
    try testing.expectEqual(null, d.time);
    const e = doc.at(&.{"e"}).datetime;
    try testing.expectEqual(null, e.date);
    try testing.expectEqual(500_000_000, e.time.?.nanosecond);
    try testing.expectEqual(toml.Time{ .hour = 13, .minute = 37 }, doc.at(&.{"f"}).datetime.time.?);
}

test "arrays: mixed, nested, over lines, with a trailing comma" {
    var doc = try parse(
        \\a = [ 1, 2, 3 ]
        \\b = [ "x", 1.5, [ true, false ] ]
        \\c = [
        \\  1, # one
        \\  2,
        \\]
        \\d = []
    );
    defer doc.deinit();
    try testing.expectEqual(3, doc.at(&.{"a"}).array.values().len);
    const b = doc.at(&.{"b"}).array.values();
    try testing.expectEqualStrings("x", b[0].string);
    try testing.expect(!b[2].array.values()[1].boolean);
    try testing.expectEqual(2, doc.at(&.{"c"}).array.values()[1].integer);
    try testing.expectEqual(0, doc.at(&.{"d"}).array.values().len);
}

test "tables, in any order, with tables inside" {
    var doc = try parse(
        \\top = 1
        \\[a.b.c]
        \\x = 1
        \\[a]
        \\y = 2
        \\[a.b]
        \\z = 3
        \\[ "d e" . f ]
    );
    defer doc.deinit();
    try testing.expectEqual(1, doc.at(&.{ "a", "b", "c", "x" }).integer);
    try testing.expectEqual(2, doc.at(&.{ "a", "y" }).integer);
    try testing.expectEqual(3, doc.at(&.{ "a", "b", "z" }).integer);
    try testing.expectEqual(0, doc.at(&.{ "d e", "f" }).table.keys().len);
}

test "a table under one made by a dotted key" {
    var doc = try parse(
        \\[fruit]
        \\apple.color = "red"
        \\[fruit.apple.texture]
        \\smooth = true
    );
    defer doc.deinit();
    try testing.expect(doc.at(&.{ "fruit", "apple", "texture", "smooth" }).boolean);
}

test "inline tables, over lines and with a trailing comma" {
    var doc = try parse(
        \\name = { first = "Tom", last = "Preston-Werner" }
        \\point = {
        \\  x = 1,
        \\  y.z = 2, # nested by a dotted key
        \\}
        \\empty = {}
    );
    defer doc.deinit();
    try testing.expectEqualStrings("Tom", doc.at(&.{ "name", "first" }).string);
    try testing.expectEqual(2, doc.at(&.{ "point", "y", "z" }).integer);
    try testing.expectEqual(0, doc.at(&.{"empty"}).table.keys().len);
}

test "arrays of tables, with tables and arrays of tables inside" {
    var doc = try parse(
        \\[[people]]
        \\handle = "alice"
        \\[people.contact]
        \\city = "Oslo"
        \\[[people.absences]]
        \\from = 2027-03-01
        \\[[people.absences]]
        \\from = 2027-07-12
        \\[[people]]
        \\handle = "bob"
    );
    defer doc.deinit();
    const people = doc.at(&.{"people"}).array;
    try testing.expect(people.of_tables);
    try testing.expectEqual(2, people.values().len);
    const alice = people.values()[0].table;
    try testing.expectEqualStrings("alice", alice.get("handle").?.string);
    try testing.expectEqualStrings("Oslo", alice.get("contact").?.table.get("city").?.string);
    try testing.expectEqual(2, alice.get("absences").?.array.values().len);
    const bob = people.values()[1].table;
    try testing.expectEqual(null, bob.get("absences"));
}
