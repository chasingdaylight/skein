//! Markers wrapped in bold (#163): read, edited and rendered as any other.

// req: items.marker.bold
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const link_command = @import("../../commands/link.zig");
const move_command = @import("../../commands/move.zig");
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

test "bold markers are checked, linked, moved and rendered bold once" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n");
    try write(tmp.dir, ".skein/links/see.toml", "from = [\"rule\"]\nto = [\"rule\"]\n");
    try write(tmp.dir, "spec/lex.md", "# Lexical\n\n**%rule[lex.a syntax]** The *first* rule.\n\n- **%rule[lex.b]** The second.\n- %rule[lex.c] The third.\n\n**%rule[lex.d] Not closed where it should be.**\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const unclosed = try check_command.run(testing.io, a, .{ .root = root });
    try expectContains(unclosed.text, "spec/lex.md:8:");
    try expectContains(unclosed.text, "closed right after its ']'");
    try write(tmp.dir, "spec/lex.md", "# Lexical\n\n**%rule[lex.a syntax]** The *first* rule.\n\n- **%rule[lex.b syntax]** The second.\n- %rule[lex.c syntax] The third.\n");
    const checked = try check_command.run(testing.io, a, .{ .root = root });
    try expectContains(checked.text, "no problems (3 items");

    try testing.expectEqual(.ok, (try link_command.run(testing.io, a, .{ .common = .{ .root = root }, .from = "lex.a", .type_name = "see", .to = "lex.b" })).status);
    try testing.expectEqual(.ok, (try move_command.run(testing.io, a, .{ .common = .{ .root = root }, .old = "lex.b", .new = "lex.bee", .alias = false })).status);
    const doc = try tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 16));
    try expectContains(doc, "**%rule[lex.a syntax see=lex.bee]** The *first* rule.\n");
    try expectContains(doc, "- **%rule[lex.bee syntax]** The second.\n");

    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir })).status);
    const page = try tmp.dir.readFileAlloc(testing.io, "out/spec/lex.md", a, .limited(1 << 16));
    try expectContains(page, "<a id=\"lex.a\"></a>**[lex.a](#lex.a)** *(syntax)* The *first* rule.\n");
    try expectContains(page, "- <a id=\"lex.bee\"></a>**[lex.bee](#lex.bee)** *(syntax)* The second.\n");
    try testing.expect(std.mem.find(u8, page, "****") == null);
}
