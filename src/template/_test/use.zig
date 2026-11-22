//! A project that uses a template: the template's types and links, the
//! project's own files over them, and what is wrong with its use.

// req: templates.use, templates.commands
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const coverage_command = @import("../../commands/coverage.zig");
const template_command = @import("../../commands/template.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

test "a project that declares nothing of its own but its template" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "template = \"langspec\"\n\n[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, "spec/lex.md",
        \\%term[lex.token] A token.
        \\
        \\%rule[lex.comment syntax see=lex.token] A comment runs to the end of the line.
        \\
        \\```cesium %example
        \\// a comment
        \\```
        \\
    );
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems (3 items of 4 types, 3 link types");
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "shows links to rule items: 1 of 1 (100%)");

    // the project's own file of a name replaces the template's
    try write(tmp.dir, ".skein/types/rule.toml", "categories = [\"syntax\", \"semantics\"]\n");
    try write(tmp.dir, "spec/more.md", "%rule[lex.more semantics] Semantics, which the template does not have.\n\n```cesium %example\nx\n```\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems (5 items");
}

test "a template that does not exist, or an option it does not have" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "template = [\"langspec\", \"nowhere\"]\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "template: skein has no template 'nowhere'");
    try write(tmp.dir, ".skein/config.toml", "[template.spec]\nname = \"langspec\"\nclass = \"C\"\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "the template 'langspec' has no option 'class'");
}

test "the templates, listed and shown" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectContains((try template_command.run(testing.io, a, .{ .what = .list })).text, "langspec  The specification of a programming language");
    const shown = (try template_command.run(testing.io, a, .{ .what = .show, .name = "langspec" })).text;
    try expectContains(shown, "Types:\n  rule.toml\n  term.toml\n  example.toml\n");
    try expectContains(shown, "Links:\n  shows.toml\n  see.toml\n");
    try expectContains((try template_command.run(testing.io, a, .{ .what = .show, .name = "nowhere" })).text, "skein has no template 'nowhere'");
}
