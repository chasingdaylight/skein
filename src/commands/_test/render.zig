//! `skein render`, on a project on disk.

// req: render.markdown, render.markdown.output
const std = @import("std");
const testing = std.testing;

const render = @import("../render.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "every source file is written under its own path" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml",
        \\[project]
        \\name = "example"
        \\[[sources]]
        \\path = "spec"
        \\[[sources]]
        \\path = "requirements"
        \\kind = "items"
        \\type = "req"
    );
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, ".skein/types/req.toml", "id = \"numbered\"\nprefix = \"R\"\n");
    try write(tmp.dir, "spec/lex/comments.md", "%rule[lex.comment] As %[R-001] asks.\n");
    try write(tmp.dir, "spec/readme.md", "No items here.\n");
    try write(tmp.dir, "requirements/R-001.md", "+++\nid = \"R-001\"\n+++\n\nSee %[lex.comment].\n");
    try write(tmp.dir, "other/notes.md", "Not in a source: %[lex.comment].\n");

    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const out_dir = try a.print("{s}/out/site", .{root});
    const outcome = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    try testing.expectEqual(.ok, outcome.status);
    try testing.expectEqualStrings(try a.print("skein: 3 files rendered to {s}\n", .{out_dir}), outcome.text);

    const read = struct {
        fn read(alloc: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]const u8 {
            return dir.readFileAlloc(testing.io, path, alloc, .limited(1 << 20));
        }
    }.read;
    try testing.expectEqualStrings(
        "<a id=\"lex.comment\"></a>**[lex.comment](#lex.comment)** As [R-001](../../requirements/R-001.md) asks.\n",
        try read(a, tmp.dir, "out/site/spec/lex/comments.md"),
    );
    try testing.expectEqualStrings("No items here.\n", try read(a, tmp.dir, "out/site/spec/readme.md"));
    try testing.expectEqualStrings(
        "---\ntitle: \"R-001\"\n---\n\nSee [lex.comment](../spec/lex/comments.md#lex.comment).\n",
        try read(a, tmp.dir, "out/site/requirements/R-001.md"),
    );
    try testing.expectError(error.FileNotFound, read(a, tmp.dir, "out/site/other/notes.md"));
    // the sources are as they were
    try testing.expectEqualStrings("%rule[lex.comment] As %[R-001] asks.\n", try read(a, tmp.dir, "spec/lex/comments.md"));
}
