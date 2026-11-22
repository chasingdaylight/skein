//! Starting a project from a template, and taking a template's files into
//! the project to change them.

// req: templates.init, templates.eject
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const init_command = @import("../../commands/init.zig");
const template_command = @import("../../commands/template.zig");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

fn rootOf(a: std.mem.Allocator, tmp: anytype) ![]const u8 {
    return tmp.dir.realPathFileAlloc(testing.io, ".", a);
}

test "init with a template starts a project that checks clean" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const started = try init_command.run(testing.io, a, .{ .root = root, .template = "langspec" });
    try testing.expectEqual(.ok, started.status);
    try expectContains(started.text, "from the template langspec, with 1 document");
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    try expectContains(config, "template = \"langspec\"");
    _ = try tmp.dir.readFileAlloc(testing.io, "docs/introduction.md", a, .limited(1 << 16));

    const checked = try check_command.run(testing.io, a, .{ .root = root });
    try testing.expectEqual(.ok, checked.status);

    const again = try init_command.run(testing.io, a, .{ .root = root });
    try testing.expectEqual(.misuse, again.status);
    try expectContains(again.text, "there is a project here already");
}

test "init without a template, and with one skein does not have" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const unknown = try init_command.run(testing.io, a, .{ .root = root, .template = "nope" });
    try testing.expectEqual(.misuse, unknown.status);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, ".skein", .{}));

    const plain = try init_command.run(testing.io, a, .{ .root = root });
    try testing.expectEqual(.ok, plain.status);
    try expectContains(plain.text, "with 0 documents");
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    try testing.expect(std.mem.find(u8, config, "template") == null);
}

test "eject writes the template's files into .skein/ and keeps the project's own" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);
    _ = try init_command.run(testing.io, a, .{ .root = root, .template = "langspec" });
    try tmp.dir.createDirPath(testing.io, ".skein/types");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/types/rule.toml", .data = "description = \"Ours\"\ncategories = [\"syntax\"]\n" });

    const ejected = try template_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .eject, .name = "langspec" });
    try testing.expectEqual(.ok, ejected.status);
    try expectContains(ejected.text, "4 files of 'langspec' written");
    try expectContains(ejected.text, "1 the project has already, left as it is");
    const rule = try tmp.dir.readFileAlloc(testing.io, ".skein/types/rule.toml", a, .limited(1 << 16));
    try expectContains(rule, "Ours");
    _ = try tmp.dir.readFileAlloc(testing.io, ".skein/links/shows.toml", a, .limited(1 << 16));

    const unused = try template_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .eject, .name = "other" });
    try testing.expectEqual(.misuse, unused.status);
    try expectContains(unused.text, "does not use the template 'other'");
}
