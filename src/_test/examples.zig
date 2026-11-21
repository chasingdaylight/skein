//! The example projects in `examples/` must check clean: they are what a
//! reader copies from.

// req: principle.git-only
const std = @import("std");
const testing = std.testing;

const check = @import("../commands/check.zig");
const coverage = @import("../commands/coverage.zig");

const examples_dir = @import("build_options").examples_dir;

fn expectClean(a: std.mem.Allocator, name: []const u8, summary: []const u8) !void {
    const root = try std.Io.Dir.path.join(a, &.{ examples_dir, name });
    const out = try check.run(testing.io, a, .{ .root = root });
    testing.expectEqual(.ok, out.status) catch |e| {
        std.debug.print("{s}", .{out.text});
        return e;
    };
    try testing.expectEqualStrings(summary, out.text);
}

test "the language specification example" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectClean(a, "language-spec", "skein: language-spec example: no problems (10 items of 2 types, 0 link types, 1 profiles, 5 citations)\n");

    // as its readme says: the core stage is covered, the full one is not
    const root = try std.Io.Dir.path.join(a, &.{ examples_dir, "language-spec" });
    const all = (try coverage.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try testing.expect(std.mem.find(u8, all, "test citations of rule items: 5 of 7 (71%)") != null);
    const core = (try coverage.run(testing.io, a, .{ .common = .{ .root = root }, .profile = "core" })).text;
    try testing.expect(std.mem.find(u8, core, "test citations of rule items: 5 of 5 (100%)") != null);
}

test "the requirements example, with its review records and its approval" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try expectClean(arena.allocator(), "requirements", "skein: requirements example: no problems (6 items of 3 types, 2 link types, 0 profiles, 2 citations)\n");
}

test "skein's own requirements, and the tests that cite them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // the repository itself: `examples` is a directory of its root
    const root = try std.Io.Dir.path.join(a, &.{ examples_dir, ".." });
    const out = try check.run(testing.io, a, .{ .root = root });
    testing.expectEqual(.ok, out.status) catch |e| {
        std.debug.print("{s}", .{out.text});
        return e;
    };
    // every requirement that is implemented has a test, but for the one
    // that is verified by reading build.zig.zon
    const implemented = (try coverage.run(testing.io, a, .{ .common = .{ .root = root }, .profile = "implemented" })).text;
    testing.expect(std.mem.find(u8, implemented, "  without:\n    principle.one-codebase\n") != null and
        std.mem.count(u8, implemented, "\n    ") == 1) catch |e| {
        std.debug.print("{s}", .{implemented});
        return e;
    };
}
