//! Mermaid diagrams in the rendered pages: drawn by mermaid.js, which a
//! site has once and a standalone document has inside it.

// req: render.mermaid
const std = @import("std");
const testing = std.testing;

const render_command = @import("../../commands/render.zig");
const vendor = @import("vendor");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack[0..@min(haystack.len, 4000)] });
        return error.TestExpectedContains;
    }
}

test "a mermaid block is a diagram, and mermaid.js comes only with one" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[project]\nname = \"Diagrams\"\n\n[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, "spec/flow/states.md", "# States\n\n```mermaid\ngraph TD\n  A --> B\n```\n");
    try write(tmp.dir, "spec/plain.md", "# Plain\n\nNo diagram.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const site = try std.Io.Dir.path.join(a, &.{ root, "site" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = site, .format = .html })).status);
    const states = try tmp.dir.readFileAlloc(testing.io, "site/spec/flow/states.html", a, .limited(1 << 20));
    try expectContains(states, "<pre class=\"mermaid\">graph TD\n  A --&gt; B\n</pre>");
    try expectContains(states, "<script src=\"../../mermaid.min.js\"></script>");
    try expectContains(states, "mermaid.initialize(");
    const plain = try tmp.dir.readFileAlloc(testing.io, "site/spec/plain.html", a, .limited(1 << 20));
    try testing.expect(std.mem.find(u8, plain, "mermaid") == null);
    const copied = try tmp.dir.readFileAlloc(testing.io, "site/mermaid.min.js", a, .limited(1 << 26));
    try testing.expectEqual(vendor.mermaid.len, copied.len);

    // a document stands alone: mermaid.js inside it
    const docs = try std.Io.Dir.path.join(a, &.{ root, "docs" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = docs, .format = .document })).status);
    const alone = try tmp.dir.readFileAlloc(testing.io, "docs/spec/flow/states.html", a, .limited(1 << 26));
    try testing.expect(alone.len > vendor.mermaid.len);
    try testing.expect(std.mem.find(u8, alone, "<script src=") == null);
    try expectContains(alone, "mermaid.initialize(");
}
