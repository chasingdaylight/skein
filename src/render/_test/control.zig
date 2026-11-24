//! Document control in rendered documents: the control table, the change
//! record from the baselines, when an item file last changed, and the
//! register of documents.

// req: render.control
const std = @import("std");
const testing = std.testing;

const baseline_command = @import("../../commands/baseline.zig");
const git_program = @import("../../git.zig");
const render_command = @import("../../commands/render.zig");

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

fn commit(a: std.mem.Allocator, dir: std.Io.Dir) !void {
    _ = try git_program.output(testing.io, a, dir, &.{ "add", "--all" });
    _ = try git_program.output(testing.io, a, dir, &.{ "-c", "user.name=A. Author", "-c", "user.email=a@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "change" });
}

test "a controlled document, its change record, and the register of documents" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "init", "--quiet" });
    // baselines are annotated tags, which need a tagger where git has no identity (CI)
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "config", "user.name", "A. Author" });
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "config", "user.email", "a@example.invalid" });
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "config", "tag.gpgSign", "false" });
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[[sources]]\npath = \"requirements\"\nkind = \"items\"\ntype = \"rule\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, "spec/sdp.md", "+++\ndocument = \"EX-SDP\"\nrevision = \"A\"\n+++\n\n# Development plan\n\n%rule[sdp.one] One.\n");
    try write(tmp.dir, "spec/index.md", "# Documents\n\n```skein\ndocuments\n```\n");
    try write(tmp.dir, "requirements/r.one.md", "+++\nid = \"r.one\"\n+++\n\nA rule in a file.\n");
    try commit(a, tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try testing.expectEqual(.ok, (try baseline_command.run(testing.io, a, .{ .common = .{ .root = root }, .name = "v1", .message = "First issue" })).status);
    try write(tmp.dir, "spec/sdp.md", "+++\ndocument = \"EX-SDP\"\nrevision = \"B\"\n+++\n\n# Development plan\n\n%rule[sdp.one] One, changed.\n\n%rule[sdp.two] Two.\n");
    try commit(a, tmp.dir);
    try testing.expectEqual(.ok, (try baseline_command.run(testing.io, a, .{ .common = .{ .root = root }, .name = "v2", .message = "Second issue" })).status);

    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    const done = try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    try testing.expectEqual(.ok, done.status);
    const sdp = try tmp.dir.readFileAlloc(testing.io, "out/spec/sdp.md", a, .limited(1 << 16));
    try expectContains(sdp, "# Development plan\n\n| Document | Revision | Last changed |\n| --- | --- | --- |\n| EX-SDP | B | ");
    try expectContains(sdp, ", by A. Author, in `");
    try expectContains(sdp, "## Change record\n\n| Baseline | Date | Message | Added | Changed | Removed |\n| --- | --- | --- | ---: | ---: | ---: |\n| v1 | ");
    try expectContains(sdp, " | First issue | 1 | 0 | 0 |\n| v2 | ");
    try expectContains(sdp, " | Second issue | 1 | 1 | 0 |\n");

    const item = try tmp.dir.readFileAlloc(testing.io, "out/requirements/r.one.md", a, .limited(1 << 16));
    try expectContains(item, "---\ntitle: \"r.one\"\nlast_changed: \"");
    try expectContains(item, "changed_by: \"A. Author\"\ncommit: \"");

    const index = try tmp.dir.readFileAlloc(testing.io, "out/spec/index.md", a, .limited(1 << 16));
    try expectContains(index, "| Document | Title | Revision | Last changed |\n| --- | --- | --- | --- |\n| EX-SDP | [Development plan](sdp.md) | B | ");
}
