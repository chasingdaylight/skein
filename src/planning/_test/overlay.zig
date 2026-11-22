//! What-if plans: deviations from the forge kept as an overlay, applied in
//! views, checked against the forge, and written back with `skein apply`;
//! the forge is stood in for by the test.

// req: planning.overlay, planning.apply
const std = @import("std");
const testing = std.testing;

const Forge = @import("../../forge/Forge.zig");
const apply_command = @import("../../commands/apply.zig");
const check_command = @import("../../commands/check.zig");
const checks = @import("../../forge/checks.zig");
const git_program = @import("../../git.zig");
const github = @import("../../forge/github.zig");
const overlay_command = @import("../../commands/overlay.zig");
const schedule_command = @import("../../commands/schedule.zig");

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

/// The forge: #1 open, ann's, in v1; what `update` was last given
var assignees: []const []const u8 = &.{"ann"};
var written: ?github.Changes = null;
var fail_write = false;

fn fake(_: std.Io, _: std.mem.Allocator, _: *const Forge, r: Forge.Ref) anyerror!github.Answer {
    if (r.number != 1) return .missing;
    return .{ .found = .{ .title = "Parser", .open = true, .pull = false, .assignees = assignees, .milestone = "v1", .due = "2027-03-12" } };
}

fn fakeUpdate(_: std.Io, _: std.mem.Allocator, _: *const Forge, _: Forge.Ref, changes: github.Changes, _: []const u8) anyerror!?[]const u8 {
    if (fail_write) return "denied";
    written = changes;
    return null;
}

test "a what-if plan: deviations recorded, applied in views, checked, and written to the forge" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    _ = try git_program.output(testing.io, a, dir, &.{ "init", "--quiet" });
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n\n[forge]\nrepository = \"example/plan\"\n");
    try write(dir, ".skein/types/task.toml", "statuses = [\"open\", \"done\"]\n[attributes.days]\ntype = \"integer\"\n[attributes.owner]\n[attributes.due]\n[attributes.issue]\n[planning]\nduration = \"days\"\nassignees = \"owner\"\nmilestone = \"due\"\nissue = \"issue\"\n");
    try write(dir, "plan/plan.md", "%task[t.parser days=3 issue=#1] The parser.\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const common: @import("../../cli.zig").Common = .{ .root = root };
    const saved_lookup = checks.lookup;
    const saved_update = checks.update;
    defer {
        checks.lookup = saved_lookup;
        checks.update = saved_update;
    }
    checks.lookup = fake;
    checks.update = fakeUpdate;
    assignees = &.{"ann"};

    // a deviation: bob does it, in the plan
    const said = (try overlay_command.run(testing.io, a, .{ .common = common, .issue = "#1", .field = "assignees", .value = "bob" })).text;
    try expectContains(said, "the plan changes assignees of example/plan#1 from 'ann' to 'bob'");
    try expectContains((try overlay_command.run(testing.io, a, .{ .common = common })).text, "example/plan#1  assignees: 'ann' -> 'bob'");
    const file = try dir.readFileAlloc(testing.io, ".skein/overlay.toml", a, .limited(1 << 16));
    try expectContains(file, "\"example/plan#1\".assignees = { base = \"ann\", value = \"bob\" }\n");
    // what it refuses
    try expectContains((try overlay_command.run(testing.io, a, .{ .common = common, .issue = "#1", .field = "state", .value = "later" })).text, "a state is open or closed");
    try expectContains((try overlay_command.run(testing.io, a, .{ .common = common, .issue = "#9", .field = "state", .value = "closed" })).text, "the forge has no issue example/plan#9");

    // views see the plan: bob's, not ann's (the load of the week of a start would show it)
    const works = (try @import("../forge.zig").collect(testing.io, a, dir, &(try loadProject(a, dir)), &(try loadGraph(a, dir)), false)).works;
    try testing.expectEqualStrings("bob", works[0].assignees[0]);

    // check is clean while the forge still says what the overlay is based on
    _ = try schedule_command.run(testing.io, a, .{ .common = common });
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    // and reports the overlay once the forge has moved
    assignees = &.{"carol"};
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "the overlay changes assignees of example/plan#1 from 'ann' to 'bob', and the forge now says 'carol'");

    // apply: not what changed on both sides, unless forced
    const refused = try apply_command.run(testing.io, a, .{ .common = common });
    try expectContains(refused.text, "changed on both sides");
    try testing.expectEqual(.problems, refused.status);
    try testing.expectEqual(null, written);
    const dry = (try apply_command.run(testing.io, a, .{ .common = common, .force = true, .dry_run = true })).text;
    try expectContains(dry, "example/plan#1 assignees: 'carol' -> 'bob' (dry run)");
    try testing.expectEqual(null, written);
    fail_write = true;
    try expectContains((try apply_command.run(testing.io, a, .{ .common = common, .force = true })).text, "not written: denied; left in the overlay");
    fail_write = false;
    const done = (try apply_command.run(testing.io, a, .{ .common = common, .force = true })).text;
    try expectContains(done, "skein: 1 deviation written to the forge, 0 left in the overlay");
    try testing.expectEqualStrings("bob", written.?.assignees.?[0]);
    // the overlay is empty, and its file gone
    try testing.expectError(error.FileNotFound, dir.access(testing.io, ".skein/overlay.toml", .{}));

    // taking a deviation out; one the forge already says is no deviation
    _ = try overlay_command.run(testing.io, a, .{ .common = common, .issue = "#1", .field = "state", .value = "closed" });
    try expectContains((try overlay_command.run(testing.io, a, .{ .common = common, .issue = "example/plan#1", .field = "state", .remove = true })).text, "state is the forge's again");
    try expectContains((try overlay_command.run(testing.io, a, .{ .common = common, .issue = "#1", .field = "state", .value = "open" })).text, "the forge says that already");
}

fn loadProject(a: std.mem.Allocator, dir: std.Io.Dir) !@import("../../Project.zig") {
    var ignored: @import("../../Report.zig") = .{ .arena = a };
    return @import("../../Project.zig").load(testing.io, a, dir, &ignored);
}

fn loadGraph(a: std.mem.Allocator, dir: std.Io.Dir) !@import("../../graph/Graph.zig") {
    var ignored: @import("../../Report.zig") = .{ .arena = a };
    const project = try loadProject(a, dir);
    return @import("../../graph/Graph.zig").load(testing.io, a, dir, &project, &ignored);
}
