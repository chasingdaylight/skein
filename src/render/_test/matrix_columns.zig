//! A generated matrix with chosen columns, as a compliance matrix uses.

// req: render.generated.matrix-columns
const std = @import("std");
const testing = std.testing;

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

test "columns of the requirement, and of each record that complies with it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/swe.toml", "[attributes.classes]\nlist = true\n\n[attributes.authority]\n");
    try write(tmp.dir, ".skein/types/comply.toml", "[attributes.state]\nvalues = [\"FC\", \"T\", \"NA\"]\n\n[attributes.evidence]\nlist = true\n");
    try write(tmp.dir, ".skein/types/doc.toml", "");
    try write(tmp.dir, ".skein/links/complies-with.toml", "from = [\"comply\"]\nto = [\"swe\"]\n");
    try write(tmp.dir, "spec/npr.md",
        \\%swe[swe.one classes=A,B,C authority=Center] Plan the software.
        \\
        \\%swe[swe.two classes=A authority=CIO] Assess security.
        \\
        \\%doc[sdp] The development plan.
        \\
        \\%comply[c.one.models complies-with=swe.one state=FC evidence=sdp] For the models.
        \\
        \\%comply[c.one.server complies-with=swe.one state=T] For the server, tailored.
        \\
        \\```skein
        \\matrix complies-with columns=text,classes,authority from.columns=state,evidence
        \\```
        \\
    );
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    const page = try tmp.dir.readFileAlloc(testing.io, "out/spec/npr.md", a, .limited(1 << 16));
    try expectContains(page,
        \\| Item | Text | Classes | Authority | `complies-with` from | State | Evidence |
        \\| --- | --- | --- | --- | --- | --- | --- |
        \\| [`swe.one`](#swe.one) | Plan the software. | A, B, C | Center | [`c.one.models`](#c.one.models) | FC | [`sdp`](#sdp) |
        \\| [`swe.one`](#swe.one) | Plan the software. | A, B, C | Center | [`c.one.server`](#c.one.server) | T |  |
        \\| [`swe.two`](#swe.two) | Assess security. | A | CIO | **none** |  |  |
        \\
        \\1 of 2 with a `complies-with` link.
    );
}
