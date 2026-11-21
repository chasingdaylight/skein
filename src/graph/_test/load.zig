//! Loading a project's items from its sources on disk.

// req: items.sources, principle.deterministic
const std = @import("std");
const testing = std.testing;

const Graph = @import("../Graph.zig");
const Project = @import("../../Project.zig");
const Report = @import("../../Report.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "items are read from every source, in the order of the files" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try write(tmp.dir, ".skein/config.toml",
        \\[[sources]]
        \\path = "spec"
        \\[[sources]]
        \\path = "requirements"
        \\kind = "items"
        \\type = "srs"
    );
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n");
    try write(tmp.dir, ".skein/links/refines.toml", "");
    try write(tmp.dir, "spec/b.md", "%rule[b.one]\nSecond file.\r\n");
    try write(tmp.dir, "spec/a/deep.md", "%rule[a.deep]\nIn a directory; see %[SRS-002].\n");
    try write(tmp.dir, "spec/notes.txt", "%rule[not.read]\nNot Markdown.\n");
    try write(tmp.dir, "requirements/SRS-002.md", "+++\nid = \"SRS-002\"\nrefines = [\"SRS-001\"]\n+++\nTwo.\n");
    try write(tmp.dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\nOne.\n");

    var report: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, tmp.dir, &report);
    const graph = try Graph.load(testing.io, a, tmp.dir, &project, &report);
    try Graph.checks.run(&graph, &project.schema, &report);
    try testing.expectEqualStrings("", try report.render(a));
    try testing.expectEqual(4, graph.items.len);
    try testing.expectEqualStrings("a.deep", graph.items[0].id);
    try testing.expectEqualStrings("spec/a/deep.md", graph.items[0].file);
    try testing.expectEqualStrings("b.one", graph.items[1].id);
    try testing.expectEqualStrings("Second file.", graph.items[1].text);
    try testing.expectEqualStrings("SRS-001", graph.items[2].id);
    try testing.expectEqualStrings("SRS-002", graph.items[3].id);
}

test "a source that is not there, and a file that is not text" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"missing\"\n[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, "spec/bad.md", "%rule[a.b]\n\xff\xfe\n");

    var report: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, tmp.dir, &report);
    const graph = try Graph.load(testing.io, a, tmp.dir, &project, &report);
    try testing.expectEqual(0, graph.items.len);
    try testing.expectEqualStrings(
        \\.skein/config.toml: error: sources: cannot read the directory 'missing' (FileNotFound)
        \\spec/bad.md: error: the file is not valid UTF-8
        \\
    , try report.render(a));
}
