//! Citations in code and tests.

// req: items.citation, items.citation.directory, check.citations
const std = @import("std");
const testing = std.testing;

const Citations = @import("../Citations.zig");
const Graph = @import("../Graph.zig");
const Project = @import("../../Project.zig");
const Report = @import("../../Report.zig");

const set: Project.CitationSet = .{ .name = "test", .path = "tests", .files = &.{".zig"}, .marker = "// spec:" };

fn expectTargets(text: []const u8, expected: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Citations.Citation) = .empty;
    try Citations.readSource(arena.allocator(), set, "tests/a.zig", text, &out);
    try testing.expectEqual(expected.len, out.items.len);
    for (out.items, expected) |c, e| try testing.expectEqualStrings(e, c.target);
}

test "the IDs after a marker, wherever it is on the line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Citations.Citation) = .empty;
    try Citations.readSource(arena.allocator(), set, "tests/a.zig",
        \\const std = @import("std");
        \\
        \\// spec: lex.comment.line, lex.comment.block  SRS-012
        \\test "comments" {
        \\    try run("x"); // spec: lex.token
        \\}
    , &out);
    try testing.expectEqual(4, out.items.len);
    try testing.expectEqualStrings("lex.comment.line", out.items[0].target);
    try testing.expectEqualStrings("test", out.items[0].set);
    try testing.expectEqual(3, out.items[0].line);
    try testing.expectEqual(10, out.items[0].column);
    try testing.expectEqualStrings("lex.comment.block", out.items[1].target);
    try testing.expectEqualStrings("SRS-012", out.items[2].target);
    try testing.expectEqualStrings("lex.token", out.items[3].target);
    try testing.expectEqual(5, out.items[3].line);
}

test "where a citation ends" {
    try expectTargets("// spec: SRS-012.", &.{"SRS-012"});
    try expectTargets("// spec: a.b, c.d. And more words.", &.{ "a.b", "c.d" });
    try expectTargets("// spec: a.b (see below)", &.{"a.b"});
    try expectTargets("// spec:\r\n// spec:a.b\r\n", &.{"a.b"});
    try expectTargets("// spec is not the marker: a.b", &.{});
    try expectTargets("// spec: other:some.rule", &.{"other:some.rule"});
}

test "a directory's file of citations" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Citations.Citation) = .empty;
    try Citations.readDirectoryFile(arena.allocator(), "test", "tests/lex/.skein-cites",
        \\# every test in this directory checks these
        \\lex.comment.line
        \\lex.token, lex.space   # two on a line
        \\
    , &out);
    try testing.expectEqual(3, out.items.len);
    try testing.expectEqualStrings("lex.space", out.items[2].target);
    try testing.expectEqual(3, out.items[2].line);
    try testing.expectEqualStrings("tests/lex/.skein-cites", out.items[2].file);
}

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "a project's citations are found and checked" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try write(tmp.dir, ".skein/config.toml",
        \\[[sources]]
        \\path = "spec"
        \\[[citations]]
        \\name = "test"
        \\path = "tests"
        \\files = [".zig"]
        \\marker = "// spec:"
        \\to = ["rule"]
        \\[[citations]]
        \\name = "code"
        \\path = "."
        \\files = [".c", ".h"]
        \\marker = "Implements "
    );
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, ".skein/types/term.toml", "");
    try write(tmp.dir, "spec/lex.md", "%rule[lex.comment]\nA comment.\n\n%term[lex.token]\nA token.\n\n%rule[lex.old removed]\n");
    try write(tmp.dir, "tests/comment.zig", "// spec: lex.comment\n// spec: lex.token, no.such\n// spec: lex.old\n");
    try write(tmp.dir, "tests/deep/.skein-cites", "lex.comment\n");
    try write(tmp.dir, "tests/deep/more.zig", "// no citation of its own");
    try write(tmp.dir, "tests/notes.txt", "// spec: not.read\n");
    try write(tmp.dir, "src/lexer.c", "/* Implements lex.comment. */\n/* Implements lex.token */\n");
    try write(tmp.dir, ".git/ignored.c", "/* Implements not.read */\n");

    var report: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, tmp.dir, &report);
    const graph = try Graph.load(testing.io, a, tmp.dir, &project, &report);
    const citations = try Citations.load(testing.io, a, tmp.dir, &project, &report);
    try citations.check(&project, &graph, &report);
    try testing.expectEqualStrings(
        \\tests/comment.zig:2:10: error: the citation names 'lex.token', a 'term', which 'test' citations do not cite
        \\tests/comment.zig:2:21: error: the citation names 'no.such', and there is no such item
        \\tests/comment.zig:3:10: error: the citation names 'lex.old', which is removed
        \\
    , try report.render(a));

    const of_comment = try citations.of(a, "lex.comment");
    try testing.expectEqual(3, of_comment.len);
    try testing.expectEqualStrings("tests/comment.zig", of_comment[0].file);
    try testing.expectEqualStrings("tests/deep/.skein-cites", of_comment[1].file);
    try testing.expectEqualStrings("code", of_comment[2].set);
    try testing.expectEqualStrings("src/lexer.c", of_comment[2].file);
}

test "citation sets that are not complete" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml",
        \\[[citations]]
        \\name = "Tests"
        \\path = "tests"
        \\files = [".zig"]
        \\marker = "// spec:"
        \\[[citations]]
        \\name = "code"
        \\marker = "  "
        \\to = ["need"]
        \\[[citations]]
        \\name = "ok"
        \\path = "missing"
        \\files = [".c"]
        \\marker = "x"
        \\to = ["need"]
    );
    var report: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, tmp.dir, &report);
    _ = try Citations.load(testing.io, a, tmp.dir, &project, &report);
    try testing.expectEqualStrings(
        \\.skein/config.toml: error: citations: cannot read the directory 'missing' (FileNotFound)
        \\.skein/config.toml: error: citations: there is no item type 'need'
        \\.skein/config.toml: error: citations[1].name: citations need a name: a name is lowercase letters, digits, '-' and '_', starting with a letter
        \\.skein/config.toml: error: citations[2].files: citations need the ends of the names of the files to read, like [".zig"]
        \\.skein/config.toml: error: citations[2].marker: citations need a marker, the text that comes before the IDs
        \\.skein/config.toml: error: citations[2].path: citations need a path
        \\
    , try report.render(a));
}
