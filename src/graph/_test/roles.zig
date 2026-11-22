//! Approvals by role: a type whose approved items each named role must
//! approve.

// req: approval.roles
const std = @import("std");
const testing = std.testing;

const approve_command = @import("../../commands/approve.zig");
const check_command = @import("../../commands/check.zig");
const trace_command = @import("../../commands/trace.zig");

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

test "an item is approved once every role has approved it as it is" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/tailoring.toml",
        \\statuses = ["draft", "approved"]
        \\
        \\[approval]
        \\statuses = ["approved"]
        \\roles = ["engineering-ta", "sma-ta"]
        \\
    );
    try write(tmp.dir, "spec/rmm.md", "%tailoring[t.cost approved] No cost estimate in dollars.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const approve = struct {
        fn run(al: std.mem.Allocator, r: []const u8, by: []const u8, as: ?[]const u8) ![]const u8 {
            return (try approve_command.run(testing.io, al, .{ .common = .{ .root = r }, .ids = &.{"t.cost"}, .by = by, .on = "2026-11-22", .as = as })).text;
        }
    }.run;

    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "t.cost: the status 'approved' needs an approval of what the item says now as engineering-ta, sma-ta");
    try testing.expectEqualStrings("skein: say in which role A. Engineer approves 't.cost': --as engineering-ta|sma-ta\n", try approve(a, root, "A. Engineer", null));
    try expectContains(try approve(a, root, "A. Engineer", "cio"), "'cio' is no role that approves a 'tailoring': engineering-ta, sma-ta");

    try testing.expectEqualStrings("skein: 1 item approved by A. Engineer as engineering-ta on 2026-11-22\n", try approve(a, root, "A. Engineer", "engineering-ta"));
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "needs an approval of what the item says now as sma-ta");
    const traced = (try trace_command.run(testing.io, a, .{ .common = .{ .root = root }, .id = "t.cost" })).text;
    try expectContains(traced, "Approved by:\n  A. Engineer on 2026-11-22 as engineering-ta\n  still to approve as: sma-ta\n");

    _ = try approve(a, root, "B. Assurance", "sma-ta");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    const records = try tmp.dir.readFileAlloc(testing.io, ".skein/approvals/spec/rmm.md.toml", a, .limited(1 << 16));
    try expectContains(records, ", as = \"sma-ta\" }");

    // a change to the item undoes both
    try write(tmp.dir, "spec/rmm.md", "%tailoring[t.cost approved] No cost estimate in dollars, nor in hours.\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "as engineering-ta, sma-ta");
}
