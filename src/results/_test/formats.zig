//! JUnit XML and TAP read into results: names, outcomes, files, items and
//! what produced them.

// req: results.junit-tap
const std = @import("std");
const testing = std.testing;

const read = @import("../read.zig");

fn records(a: std.mem.Allocator, format: read.Format, text: []const u8) ![]const read.Record {
    var why: []const u8 = "";
    return read.records(a, format, text, &why) catch |e| {
        std.debug.print("{s}\n", .{why});
        return e;
    };
}

test "JUnit XML: outcomes, the file of the case or its suite, and properties" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rs = try records(a, .junit,
        \\<?xml version="1.0"?>
        \\<testsuites>
        \\  <testsuite name="lex" file="./tests/lex.zig">
        \\    <properties><property name="implementation" value="cesium0"/></properties>
        \\    <testcase name="pass"/>
        \\    <testcase name="fail" file="tests\other.zig"><failure message="no">trace</failure></testcase>
        \\    <testcase name="error"><error/></testcase>
        \\    <testsuite name="inner">
        \\      <testcase name="skip"><skipped message="later"/>
        \\        <properties>
        \\          <property name="item" value="tp.one"/>
        \\          <property name="items" value="a, b"/>
        \\          <property name="items">c</property>
        \\        </properties>
        \\      </testcase>
        \\    </testsuite>
        \\  </testsuite>
        \\</testsuites>
    );
    try testing.expectEqual(4, rs.len);
    try testing.expectEqualStrings("pass", rs[0].get("result").?);
    try testing.expectEqualStrings("tests/lex.zig", rs[0].get("file").?);
    try testing.expectEqualStrings("cesium0", rs[0].get("implementation").?);
    try testing.expectEqualStrings("fail", rs[1].get("result").?);
    try testing.expectEqualStrings("no", rs[1].get("note").?);
    try testing.expectEqualStrings("tests/other.zig", rs[1].get("file").?);
    try testing.expectEqualStrings("fail", rs[2].get("result").?);
    try testing.expectEqualStrings("skip", rs[3].get("result").?);
    try testing.expectEqualStrings("later", rs[3].get("note").?);
    try testing.expectEqualStrings("tests/lex.zig", rs[3].get("file").?);
    try testing.expectEqualStrings("cesium0", rs[3].get("implementation").?);
    try testing.expectEqualStrings("tp.one", rs[3].get("item").?);
    try testing.expectEqual(3, rs[3].list("items").len);
    try testing.expectEqualStrings("c", rs[3].list("items")[2]);

    var why: []const u8 = "";
    try testing.expectError(error.BadResults, read.records(a, .junit, "<report/>", &why));
    try testing.expectEqualStrings("JUnit XML has 'testsuites' or 'testsuite' at its root", why);
    try testing.expectError(error.BadResults, read.records(a, .junit, "<testsuite><testcase></testsuite>", &why));
    try testing.expectEqualStrings("1:22: 'testcase' ends with '</testsuite>'", why);
}

test "TAP: outcomes, directives, subtests, files from comments and YAML blocks" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rs = try records(a, .tap,
        \\TAP version 13
        \\# implementation: cesium1
        \\# version: 0.2.0
        \\1..5
        \\# file: tests/lex.zig
        \\ok 1 - line comment
        \\not ok 2 - block comment
        \\  ---
        \\  message: "expected */"
        \\  file: .\tests\block.zig
        \\  items:
        \\    - lex.block
        \\  ...
        \\ok 3 # SKIP no input
        \\not ok 4 - later # TODO not built
        \\    ok 1 - a subtest
        \\okay this is not a test
        \\Bail out! the runner crashed
    );
    try testing.expectEqual(6, rs.len);
    try testing.expectEqualStrings("line comment", rs[0].get("test").?);
    try testing.expectEqualStrings("pass", rs[0].get("result").?);
    try testing.expectEqualStrings("tests/lex.zig", rs[0].get("file").?);
    try testing.expectEqualStrings("cesium1", rs[0].get("implementation").?);
    try testing.expectEqualStrings("0.2.0", rs[0].get("version").?);
    try testing.expectEqualStrings("fail", rs[1].get("result").?);
    try testing.expectEqualStrings("tests/block.zig", rs[1].get("file").?);
    try testing.expectEqualStrings("lex.block", rs[1].list("items")[0]);
    try testing.expectEqualStrings("skip", rs[2].get("result").?);
    try testing.expectEqualStrings("no input", rs[2].get("note").?);
    try testing.expectEqual(null, rs[2].get("test"));
    try testing.expectEqualStrings("skip", rs[3].get("result").?);
    try testing.expectEqualStrings("later", rs[3].get("test").?);
    try testing.expectEqualStrings("a subtest", rs[4].get("test").?);
    try testing.expectEqualStrings("Bail out!", rs[5].get("test").?);
    try testing.expectEqualStrings("fail", rs[5].get("result").?);
    try testing.expectEqualStrings("the runner crashed", rs[5].get("note").?);

    var why: []const u8 = "";
    try testing.expectError(error.BadResults, read.records(a, .tap, "ok 1\n  ---\n  file: x\n", &why));
    try testing.expectEqualStrings("2: a YAML block without its closing '...'", why);
}
