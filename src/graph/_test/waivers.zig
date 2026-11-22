//! Waivers in coverage and in a compliance matrix: a link type that counts
//! as another, and one that excuses from it.

// req: standards.waivers, standards.external
const std = @import("std");
const testing = std.testing;

const coverage_command = @import("../../commands/coverage.zig");
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

test "a waiver counts as compliance, or excuses from it, while it is in force" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/swe.toml", "");
    try write(tmp.dir, ".skein/types/req.toml", "");
    try write(tmp.dir, ".skein/types/waiver.toml", "statuses = [\"draft\", \"approved\"]\napproval = [\"approved\"]\n");
    try write(tmp.dir, ".skein/links/complies-with.toml", "from = [\"req\"]\nto = [\"swe\"]\nexpected = true\n");
    try write(tmp.dir, ".skein/links/waives.toml", "from = [\"waiver\"]\nto = [\"swe\"]\nexcuses = \"complies-with\"\n");
    try write(tmp.dir, ".skein/links/tailors.toml", "from = [\"waiver\"]\nto = [\"swe\"]\ncounts_as = \"complies-with\"\n");
    try write(tmp.dir, "spec/npr.md",
        \\%swe[swe.one] One.
        \\
        \\%swe[swe.two] Two.
        \\
        \\%swe[swe.three] Three.
        \\
        \\%swe[swe.four] Four.
        \\
        \\%req[req.a complies-with=swe.one] Complies.
        \\
        \\%waiver[w.two approved waives=swe.two] Waived, and approved.
        \\
        \\%waiver[w.three waives=swe.three] Waived, but not approved yet.
        \\
        \\%waiver[w.four approved tailors=swe.four] Tailored, as good as compliance.
        \\
        \\```skein
        \\matrix complies-with
        \\```
        \\
    );
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const out = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(out, "complies-with links to swe items: 2 of 3 (66%), 1 waived\n  without:\n    swe.three\n  waived:\n    swe.two\n");

    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    const page = try tmp.dir.readFileAlloc(testing.io, "out/spec/npr.md", a, .limited(1 << 16));
    try expectContains(page, "| [`swe.two`](#swe.two) |  | waived by [`w.two`](#w.two) |");
    try expectContains(page, "| [`swe.four`](#swe.four) |  | tailors by [`w.four`](#w.four) |");
    try expectContains(page, "| [`swe.three`](#swe.three) |  | **none** |");
    try expectContains(page, "2 of 3 with a `complies-with` link, 1 waived.");
}
