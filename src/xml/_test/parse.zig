//! The XML reader: what it reads into the tree, and what it refuses.

const std = @import("std");
const testing = std.testing;

const xml = @import("../../xml.zig");

fn parseOk(arena: std.mem.Allocator, source: []const u8) !*const xml.Element {
    var diag: xml.Diagnostic = .{};
    return xml.parse(arena, source, &diag) catch |e| {
        std.debug.print("{d}:{d}: {s}\n", .{ diag.line, diag.column, diag.message });
        return e;
    };
}

test "elements, attributes, text, CDATA and entities" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try parseOk(a,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE suites [ <!ENTITY x "y"> ]>
        \\<!-- a comment -->
        \\<testsuites name='all'>
        \\  <testsuite name="lex" file="tests/lex.zig">
        \\    <testcase name="a &lt; b &amp;&#65;&#x42;" time="0.1"/>
        \\    <testcase name="c"><failure message="&quot;no&quot;">trace<![CDATA[ <raw> & ]]>end</failure></testcase>
        \\    <r:item r:id="x">é</r:item>
        \\  </testsuite>
        \\</testsuites>
        \\
    );
    try testing.expectEqualStrings("testsuites", root.name);
    try testing.expectEqualStrings("all", root.attribute("name").?);
    const suite = root.child("testsuite").?;
    try testing.expectEqual(5, suite.line);
    try testing.expectEqualStrings("tests/lex.zig", suite.attribute("file").?);
    const cases = try suite.children(a, "testcase");
    try testing.expectEqual(2, cases.len);
    try testing.expectEqualStrings("a < b &AB", cases[0].attribute("name").?);
    const failure = cases[1].child("failure").?;
    try testing.expectEqualStrings("\"no\"", failure.attribute("message").?);
    try testing.expectEqualStrings("trace <raw> & end", try failure.text(a));
    const item = suite.child("item").?;
    try testing.expectEqualStrings("r:item", item.name);
    try testing.expectEqualStrings("x", item.attribute("id").?);
    try testing.expectEqualStrings("é", try item.text(a));
}

test "what is not well formed is refused, with where" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { []const u8, []const u8, u32 }{
        .{ "<a><b></a>", "'b' ends with '</a>'", 1 },
        .{ "<a>\n<b x=1/></a>", "expected a quoted value", 2 },
        .{ "<a>&nope;</a>", "'&nope;' is not an entity skein knows", 1 },
        .{ "<a>", "'a' does not end", 1 },
        .{ "<a/><b/>", "text after the root element", 1 },
        .{ "just text", "expected the root element", 1 },
        .{ "<a x=\"1\"y=\"2\"/>", "expected a space, '>' or '/>' after a name", 1 },
    };
    for (cases) |c| {
        var diag: xml.Diagnostic = .{};
        try testing.expectError(error.InvalidXml, xml.parse(a, c[0], &diag));
        try testing.expectEqualStrings(c[1], diag.message);
        try testing.expectEqual(c[2], diag.line);
    }
}

test "text is escaped for writing" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try xml.escape(&out.writer, "a < b & \"c\" 'd' >");
    try testing.expectEqualStrings("a &lt; b &amp; &quot;c&quot; &apos;d&apos; &gt;", out.written());
}
