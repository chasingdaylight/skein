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

test "the language specification example, from the langspec template" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectClean(a, "langspec", "skein: calc: no problems (18 items of 4 types, 3 link types, 1 profiles, 5 citations)\n");

    // as its readme says: the core stage is covered, the full one is not
    const root = try std.Io.Dir.path.join(a, &.{ examples_dir, "langspec" });
    const all = (try coverage.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try testing.expect(std.mem.find(u8, all, "test citations of rule items: 5 of 7 (71%)") != null);
    const core = (try coverage.run(testing.io, a, .{ .common = .{ .root = root }, .profile = "core" })).text;
    try testing.expect(std.mem.find(u8, core, "test citations of rule items: 5 of 5 (100%)") != null);
    try testing.expect(std.mem.find(u8, core, "shows links to rule items: 5 of 5 (100%)") != null);
}

test "the NPR 7150.2D example, from the npr7150.2d template, at SRR" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectClean(a, "npr7150.2d", "skein: rover: no problems (865 items of 16 types, 11 link types, 2 profiles, 6 citations)\n");

    // as its readme says: traced and verified, the matrix begun
    const root = try std.Io.Dir.path.join(a, &.{ examples_dir, "npr7150.2d" });
    const out = (try coverage.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    for ([_][]const u8{
        "derives links to system items: 3 of 3 (100%)",
        "satisfies links to requirement items: 4 of 4 (100%)",
        "verifies links to requirement items: 4 of 4 (100%)",
        "code citations of design items: 3 of 3 (100%)",
        "complies links to swe items: 6 of 88 (6%)",
        "      SRS-004",
    }) |line| testing.expect(std.mem.find(u8, out, line) != null) catch |e| {
        std.debug.print("expected '{s}' in:\n{s}", .{ line, out });
        return e;
    };
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
