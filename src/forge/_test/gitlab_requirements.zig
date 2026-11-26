//! GitLab's requirements through files: the CSV for its import, the map
//! read from its export, and the requirements report from the results.

// req: forge.gitlab-requirements
const std = @import("std");
const testing = std.testing;

const coverage_command = @import("../../commands/coverage.zig");
const export_command = @import("../../commands/export.zig");
const import_gitlab = @import("../../commands/import_gitlab.zig");

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

test "export for GitLab's import, map from its export, report from the results" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[[citations]]\nname = \"test\"\npath = \"tests\"\nfiles = [\".zig\"]\nmarker = \"// req:\"\nto = [\"req\"]\n");
    try write(dir, ".skein/types/req.toml", "statuses = [\"draft\", \"removed\"]\ntombstone = \"removed\"\n");
    try write(dir, "spec/all.md",
        \\%req[io.read] Skein shall read files. All of them, "quoted".
        \\
        \\%req[io.write] Skein shall write files.
        \\
        \\%req[io.none] Untested.
        \\
        \\%req[io.gone removed] Removed.
        \\
    );
    try write(dir, "tests/read.zig", "// req: io.read\n");
    try write(dir, "tests/write.zig", "// req: io.write\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);

    const exported = (try export_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .@"gitlab-requirements" })).text;
    try testing.expectEqualStrings(
        \\title,description
        \\io.read: Skein shall read files.,"Skein shall read files. All of them, ""quoted""."
        \\io.write: Skein shall write files.,Skein shall write files.
        \\io.none: Untested.,Untested.
        \\
    , exported);

    // what GitLab's export gives back, after the import
    try write(dir, "requirements.csv",
        \\Requirement ID,Title,Description,Author,Author Username,Created At (UTC),State,State Updated At (UTC)
        \\1,io.read: Skein shall read files.,x,A,a,2026-11-26,opened,2026-11-26
        \\2,io.write: Skein shall write files.,x,A,a,2026-11-26,opened,2026-11-26
        \\3,io.none: Untested.,x,A,a,2026-11-26,opened,2026-11-26
        \\4,A requirement made in GitLab,x,A,a,2026-11-26,opened,2026-11-26
        \\5,io.read: an old one,x,A,a,2026-11-26,archived,2026-11-26
        \\
    );
    const csv_path = try std.Io.Dir.path.join(a, &.{ root, "requirements.csv" });
    const imported = (try import_gitlab.run(testing.io, a, .{ .common = .{ .root = root }, .format = .@"gitlab-requirements", .paths = &.{csv_path} })).text;
    try testing.expectEqualStrings("skein: recorded the GitLab requirements of 3 items in .skein/gitlab-requirements.toml\n1 requirement names no item:\n  A requirement made in GitLab\n", imported);
    try expectContains(try dir.readFileAlloc(testing.io, ".skein/gitlab-requirements.toml", a, .limited(1 << 16)), "\"io.read\" = 1\n\"io.write\" = 2\n\"io.none\" = 3\n");

    try write(dir, "run.toml", "[[result]]\nfile = \"tests/read.zig\"\nresult = \"pass\"\n\n[[result]]\nfile = \"tests/write.zig\"\nresult = \"fail\"\nimplementation = \"other\"\n");
    const report_path = try std.Io.Dir.path.join(a, &.{ root, "requirements.json" });
    const files = [_][]const u8{try std.Io.Dir.path.join(a, &.{ root, "run.toml" })};
    _ = try coverage_command.run(testing.io, a, .{ .common = .{ .root = root }, .results = .{ .files = &files }, .gitlab_requirements = report_path });
    try testing.expectEqualStrings("{\"1\":\"passed\",\"2\":\"failed\"}\n", try dir.readFileAlloc(testing.io, "requirements.json", a, .limited(1 << 16)));

    // without a map there is nothing to report
    try dir.deleteFile(testing.io, ".skein/gitlab-requirements.toml");
    const refused = try coverage_command.run(testing.io, a, .{ .common = .{ .root = root }, .gitlab_requirements = report_path });
    try testing.expectEqual(.misuse, refused.status);
    try expectContains(refused.text, "run skein import gitlab-requirements first");
    const not_gitlab = try import_gitlab.run(testing.io, a, .{ .common = .{ .root = root }, .format = .@"gitlab-requirements", .paths = &.{try std.Io.Dir.path.join(a, &.{ root, "run.toml" })} });
    try testing.expectEqual(.misuse, not_gitlab.status);
}
