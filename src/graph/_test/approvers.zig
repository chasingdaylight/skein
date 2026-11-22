//! Who may approve: a type that names the people whose approval counts.

// req: approval.approvers
const std = @import("std");
const testing = std.testing;

const Approvals = @import("../Approvals.zig");
const approve_command = @import("../../commands/approve.zig");
const check_command = @import("../../commands/check.zig");
const Outcome = @import("../../commands/Workspace.zig").Outcome;

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

test "an approval counts only when given by someone the type lets approve" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/proposal.toml", "statuses = [\"draft\", \"accepted\"]\napproval = [\"accepted\"]\n");
    try write(tmp.dir, "spec/p.md", "%proposal[p.a accepted] One documentation system.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const approve = struct {
        fn run(al: std.mem.Allocator, r: []const u8, by: []const u8) !Outcome {
            return approve_command.run(testing.io, al, .{ .common = .{ .root = r }, .ids = &.{"p.a"}, .by = by, .on = "2026-11-22" });
        }
    }.run;

    // anyone may, until the type says who
    _ = try approve(a, root, "bot");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");

    try write(tmp.dir, ".skein/types/proposal.toml", "statuses = [\"draft\", \"accepted\"]\n\n[approval]\nstatuses = [\"accepted\"]\napprovers = [\"emanspeaks\"]\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "p.a: the status 'accepted' needs an approval by emanspeaks; bot approved it, who may not");

    // and the command refuses an approval that would not count
    const refused = try approve(a, root, "bot");
    try testing.expectEqual(.misuse, refused.status);
    try expectContains(refused.text, "bot may not approve 'p.a'; those who may: emanspeaks");

    _ = try approve(a, root, "emanspeaks");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
}

test "who may approve in each role, and a role the type does not have" {
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
        \\[approval.approvers]
        \\engineering-ta = ["ann"]
        \\sma-ta = ["bob"]
        \\cio = ["carol"]
        \\
    );
    try write(tmp.dir, "spec/rmm.md", "%tailoring[t.cost approved] No cost estimate in dollars.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "'cio' is not one of the roles");
    try write(tmp.dir, ".skein/types/tailoring.toml",
        \\statuses = ["draft", "approved"]
        \\
        \\[approval]
        \\statuses = ["approved"]
        \\roles = ["engineering-ta", "sma-ta"]
        \\
        \\[approval.approvers]
        \\engineering-ta = ["ann"]
        \\sma-ta = ["bob"]
        \\
    );
    const as = struct {
        fn run(al: std.mem.Allocator, r: []const u8, by: []const u8, role: []const u8) ![]const u8 {
            return (try approve_command.run(testing.io, al, .{ .common = .{ .root = r }, .ids = &.{"t.cost"}, .by = by, .on = "2026-11-22", .as = role })).text;
        }
    }.run;
    try expectContains(try as(a, root, "ann", "sma-ta"), "ann may not approve 't.cost' as sma-ta; those who may: bob");
    _ = try as(a, root, "ann", "engineering-ta");
    _ = try as(a, root, "bob", "sma-ta");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
}

test "how a reviewer approves: plainly, in the role they act in, or not at all" {
    const Schema = @import("../../schema/Schema.zig");
    const plain: Schema.ItemType = .{ .name = "p", .approvers = &.{"emanspeaks"} };
    try testing.expectEqual(.plain, Approvals.basisOf(&plain, "emanspeaks"));
    try testing.expectEqual(.none, Approvals.basisOf(&plain, "bot"));
    const open: Schema.ItemType = .{ .name = "o" };
    try testing.expectEqual(.plain, Approvals.basisOf(&open, "anyone"));
    const roles: Schema.ItemType = .{ .name = "r", .approval_roles = &.{ "a", "b" }, .role_approvers = &.{.{ .role = "b", .people = &.{"bob"} }} };
    try testing.expectEqualStrings("b", Approvals.basisOf(&roles, "bob").role);
    try testing.expectEqual(.none, Approvals.basisOf(&roles, "ann"));
}
