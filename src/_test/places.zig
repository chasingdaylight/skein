//! The places a project's files are read from, and their files.

// req: serve.static-edit, serve.site
const std = @import("std");
const testing = std.testing;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const places = @import("../places.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "the configuration, the sources' Markdown, the citations' files and the results" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"x\"\n[[sources]]\npath = \"spec\"\n[[citations]]\nname = \"test\"\npath = \".\"\nfiles = [\".zig\"]\nmarker = \"// req:\"\n[results]\npaths = [\"results.json\"]\n");
    try write(dir, ".skein/types/rule.toml", "");
    try write(dir, "spec/a.md", "%rule[a] A.\n");
    try write(dir, "spec/picture.png", "png");
    try write(dir, "src/main.zig", "// req: a\n");
    try write(dir, "src/notes.txt", "not read");
    try write(dir, "data/.skein-cites", "a\n");
    try write(dir, "results.json", "{}");
    try write(dir, "zig-out/bin/x.zig", "// a build's copy");

    var report: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, dir, &report);
    try testing.expect(report.ok());
    const found = try places.list(testing.io, a, dir, try places.of(a, &project, .check));
    const want = [_][]const u8{ ".skein/config.toml", ".skein/types/rule.toml", "spec/a.md", "data/.skein-cites", "src/main.zig", "results.json" };
    try testing.expectEqual(want.len, found.len);
    for (want, found) |w, f| try testing.expectEqualStrings(w, f);
    // for the site, the pictures beside the documents too
    const site = try places.list(testing.io, a, dir, try places.of(a, &project, .site));
    try testing.expectEqual(want.len + 1, site.len);
    try testing.expectEqualStrings("spec/picture.png", site[3]);
}
