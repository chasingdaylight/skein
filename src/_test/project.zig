//! Loading a project from a `.skein/` directory on disk.

// req: project.root, project.config, project.paths, project.files-by-name, project.unknown-keys
const std = @import("std");
const testing = std.testing;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "a project's configuration and schema are loaded from its files" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try write(tmp.dir, ".skein/config.toml",
        \\[project]
        \\name = "example"
        \\[[sources]]
        \\path = "docs/spec/"
        \\[[sources]]
        \\path = "docs/requirements"
        \\kind = "items"
        \\type = "srs"
    );
    try write(tmp.dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "categories = [\"syntax\", \"legality\"]\n");
    try write(tmp.dir, ".skein/types/notes.txt", "not a type");
    try write(tmp.dir, ".skein/links/refines.toml", "from = [\"srs\"]\nto = [\"srs\"]\n");
    try write(tmp.dir, ".skein/profiles/core.toml", "types = [\"rule\"]\n");

    var report: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, tmp.dir, &report);
    try testing.expectEqualStrings("", try report.render(a));
    try testing.expectEqualStrings("example", project.name);
    try testing.expectEqual(2, project.sources.len);
    try testing.expectEqualStrings("docs/spec", project.sources[0].path);
    try testing.expectEqual(.documents, project.sources[0].kind);
    try testing.expectEqual(.items, project.sources[1].kind);
    try testing.expectEqualStrings("srs", project.sources[1].item_type.?);
    // by name, whatever order the directory lists them in
    try testing.expectEqual(2, project.schema.types.len);
    try testing.expectEqualStrings("rule", project.schema.types[0].name);
    try testing.expectEqualStrings("srs", project.schema.types[1].name);
    try testing.expectEqual(1, project.schema.links.len);
    try testing.expectEqual(1, project.schema.profiles.len);
}

test "mistakes in a project's files are reported with their files" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try write(tmp.dir, ".skein/config.toml",
        \\[project]
        \\title = "example"
        \\[[sources]]
        \\path = "../elsewhere"
        \\[[sources]]
        \\path = "docs"
        \\kind = "files"
        \\[[sources]]
        \\path = "requirements"
        \\kind = "items"
        \\type = "need"
    );
    try write(tmp.dir, ".skein/types/Rule.toml", "");
    try write(tmp.dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \n");
    try write(tmp.dir, ".skein/links/verifies.toml", "to = [\"rule\"]\n");

    var report: Report = .{ .arena = a };
    _ = try Project.load(testing.io, a, tmp.dir, &report);
    try testing.expectEqualStrings(
        \\.skein/config.toml: error: project.title: unknown key
        \\.skein/config.toml: error: sources: there is no item type 'need'
        \\.skein/config.toml: error: sources[1].path: a path is written from the project's root, with forward slashes
        \\.skein/config.toml: error: sources[2].kind: expected "documents" or "items"
        \\.skein/links/verifies.toml: error: to: there is no item type 'rule'
        \\.skein/types/Rule.toml: error: the file's name is the name it declares: a name is lowercase letters, digits, '-' and '_', starting with a letter
        \\.skein/types/srs.toml:2:10: error: expected a value
        \\
    , try report.render(a));
}

test "a project without a configuration file says so" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, ".skein");

    var report: Report = .{ .arena = a };
    _ = try Project.load(testing.io, a, tmp.dir, &report);
    try testing.expectEqualStrings(
        \\.skein/config.toml: error: cannot read the file (FileNotFound)
        \\
    , try report.render(a));
}

test "the root is found from a directory inside the project" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "project/.skein");
    try tmp.dir.createDirPath(testing.io, "project/docs/spec");

    const base = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const inside = try std.Io.Dir.path.join(a, &.{ base, "project", "docs", "spec" });
    const expected = try std.Io.Dir.path.join(a, &.{ base, "project" });
    try testing.expectEqualStrings(expected, (try Project.findRoot(testing.io, a, inside)).?);
}
