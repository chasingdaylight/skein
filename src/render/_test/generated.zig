//! Generated pages in documents, rendered as Markdown and as HTML.

// req: render.generated, render.generated.list, render.generated.matrix, render.generated.coverage
const std = @import("std");
const testing = std.testing;

const render = @import("../../commands/render.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

const spec =
    \\# Lexical structure
    \\
    \\%rule[lex.a syntax stage=s0] First | rule.
    \\Its second line.
    \\
    \\More of it.
    \\
    \\%rule[lex.b legality] Second rule.
    \\
    \\%rule[lex.old removed]
    \\
    \\%term[t.token] A token.
    \\
    \\## Rules
    \\
    \\```skein
    \\list rule
    \\```
    \\
    \\## Syntax at stage s0
    \\
    \\```skein
    \\list rule category=syntax stage=s0
    \\```
    \\
    \\## Matrix
    \\
    \\```skein
    \\matrix verifies
    \\```
    \\
    \\## Coverage
    \\
    \\```skein
    \\coverage
    \\```
    \\
    \\## Wrong
    \\
    \\```skein
    \\table everything
    \\```
    \\
    \\```zig
    \\list rule
    \\```
    \\
;

fn project(dir: std.Io.Dir) !void {
    try write(dir, ".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n[[sources]]\npath = \"tests\"\n");
    try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\", \"legality\"]\n[attributes.stage]\n");
    try write(dir, ".skein/types/term.toml", "");
    try write(dir, ".skein/types/case.toml", "");
    try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nto = [\"rule\"]\nexpected = true\n");
    try write(dir, "spec/lex.md", spec);
    try write(dir, "tests/cases.md", "%case[c.one verifies=lex.a] Checks.\n");
}

test "a document's requests are replaced by the pages they ask for" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    _ = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = try a.print("{s}/md", .{root}) });
    const md = try tmp.dir.readFileAlloc(testing.io, "md/spec/lex.md", a, .limited(1 << 20));

    const expected =
        \\## Rules
        \\
        \\| Item | Category | Status | Text |
        \\| --- | --- | --- | --- |
        \\| [`lex.a`](#lex.a) | syntax | draft | First \| rule. Its second line. |
        \\| [`lex.b`](#lex.b) | legality | draft | Second rule. |
        \\
        \\## Syntax at stage s0
        \\
        \\| Item | Category | Status | Text |
        \\| --- | --- | --- | --- |
        \\| [`lex.a`](#lex.a) | syntax | draft | First \| rule. Its second line. |
        \\
        \\## Matrix
        \\
        \\| Item | Category | `verifies` from |
        \\| --- | --- | --- |
        \\| [`lex.a`](#lex.a) | syntax | [`c.one`](../tests/cases.md#c.one) |
        \\| [`lex.b`](#lex.b) | legality | **none** |
        \\
        \\1 of 2 with a `verifies` link.
        \\
        \\## Coverage
        \\
        \\| Expected | Of | Covered | |
        \\| --- | --- | ---: | ---: |
        \\| `verifies` links | `rule` items | 1 of 2 | 50% |
        \\
        \\Without a `verifies` link: [`lex.b`](#lex.b).
        \\
        \\## Wrong
        \\
        \\> **skein:** 'table' is no request skein knows: list, matrix, coverage, documents or gantt
        \\
        \\```zig
        \\list rule
        \\```
        \\
    ;
    try testing.expectEqualStrings(expected, md[std.mem.find(u8, md, "## Rules").?..]);

    // and as HTML: the same, as tables
    _ = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = try a.print("{s}/html", .{root}), .format = .html });
    const page = try tmp.dir.readFileAlloc(testing.io, "html/spec/lex.html", a, .limited(1 << 20));
    try testing.expect(std.mem.find(u8, page, "<td><a href=\"../tests/cases.html#c.one\"><code>c.one</code></a></td>") != null);
    try testing.expect(std.mem.find(u8, page, "<td><strong>none</strong></td>") != null);
}
