//! Burndown and burnup: a milestone's scope and the work done, day by day,
//! from the project as committed at the end of each day and as it is today.

// req: planning.burn
// cspell:ignore xychart
const std = @import("std");
const testing = std.testing;

const Graph = @import("../../graph/Graph.zig");
const Project = @import("../../Project.zig");
const Report = @import("../../Report.zig");
const Work = @import("../Work.zig");
const burn = @import("../burn.zig");
const day = @import("../day.zig");
const git = @import("../../git.zig");
const render_command = @import("../../commands/render.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn commit(a: std.mem.Allocator, dir: std.Io.Dir, date: []const u8) !void {
    _ = try git.output(testing.io, a, dir, &.{ "add", "--all" });
    _ = (try git.output(testing.io, a, dir, &.{ "commit", "--quiet", "--no-gpg-sign", "-m", "plan", try a.print("--date={s}T12:00:00", .{date}) })) orelse return error.CommitFailed;
}

const task_type =
    \\statuses = ["open", "doing", "done"]
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.due]
    \\[planning]
    \\duration = "days"
    \\milestone = "due"
    \\
;

test "a milestone's scope and work done, from each day's commit and from today's files" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    _ = try git.output(testing.io, a, dir, &.{ "init", "--quiet" });
    _ = try git.output(testing.io, a, dir, &.{ "config", "user.name", "A. Author" });
    _ = try git.output(testing.io, a, dir, &.{ "config", "user.email", "a@example.invalid" });
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(dir, ".skein/types/task.toml", task_type);

    // Monday: three tasks of v1
    try write(dir, "plan/plan.md", "%task[t.a days=2 due=v1] A.\n\n%task[t.b days=3 due=v1] B.\n\n%task[t.c days=1 due=v1] C.\n\n%task[t.d due=v2] Not of v1.\n");
    try commit(a, dir, "2027-03-01");
    // Wednesday: one done, and one more added
    try write(dir, "plan/plan.md", "%task[t.a days=2 due=v1 done] A.\n\n%task[t.b days=3 due=v1] B.\n\n%task[t.c days=1 due=v1] C.\n\n%task[t.e days=4 due=v1] E.\n\n%task[t.d due=v2] Not of v1.\n");
    try commit(a, dir, "2027-03-03");
    // the commit dates as the author dates, so that each day has its commit
    _ = try git.output(testing.io, a, dir, &.{ "rebase", "--quiet", "--root", "--committer-date-is-author-date" });
    // today, in the files: another done, not committed
    try write(dir, "plan/plan.md", "%task[t.a days=2 due=v1 done] A.\n\n%task[t.b days=3 due=v1 done] B.\n\n%task[t.c days=1 due=v1] C.\n\n%task[t.e days=4 due=v1] E.\n\n%task[t.d due=v2] Not of v1.\n");

    var ignored: Report = .{ .arena = a };
    const project = try Project.load(testing.io, a, dir, &ignored);
    const graph = try Graph.load(testing.io, a, dir, &project, &ignored);
    const first = day.parse("2027-02-28").?;
    const today = day.parse("2027-03-05").?;
    const works = try Work.collect(a, &project.schema, &graph);
    const points = try burn.compute(testing.io, a, dir, .{ .works = works }, "v1", first, day.parse("2027-03-12").?, today, .items);
    // the day before the first commit, then each day to today
    try testing.expectEqual(6, points.len);
    const want = [_][2]f64{ .{ 0, 0 }, .{ 3, 0 }, .{ 3, 0 }, .{ 4, 1 }, .{ 4, 1 }, .{ 4, 2 } };
    for (want, points) |w, p| {
        try testing.expectEqual(w[0], p.total);
        try testing.expectEqual(w[1], p.done);
    }
    // by weight: the durations
    const weighed = try burn.compute(testing.io, a, dir, .{ .works = works }, "v1", today, today, today, .weight);
    try testing.expectEqual(10, weighed[0].total);
    try testing.expectEqual(5, weighed[0].done);
}

// req: render.burn
test "burndown and burnup requests in a document" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    _ = try git.output(testing.io, a, dir, &.{ "init", "--quiet" });
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(dir, ".skein/types/task.toml", task_type);
    try write(dir, "plan/plan.md", "%task[t.a days=2 due=v1 done] A.\n\n%task[t.b days=3 due=v1] B.\n");
    const today = @as(day.Day, @intCast(@divFloor(std.Io.Clock.real.now(testing.io).toSeconds(), 86400)));
    const from = day.format(today - 1);
    const to = day.format(today + 3);
    try write(dir, "plan/charts.md", try a.print("# Charts\n\n```skein\nburndown v1 from={s} to={s}\n```\n\n```skein\nburnup v1 weight from={s} to={s}\n```\n\n```skein\nburndown v9\n```\n", .{ &from, &to, &from, &to }));
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    const page = try dir.readFileAlloc(testing.io, "out/plan/charts.md", a, .limited(1 << 16));
    // nothing committed: yesterday has none of it; today has the files
    try expectContains(page, "xychart-beta\n  title \"Burndown of v1\"\n");
    try expectContains(page, "  line [0, 1]\n  line [0, 0]\n");
    try expectContains(page, try a.print("| {s} | 2 | 1 | 1 |\n", .{&day.format(today)}));
    // by weight: the scope of 5 days, 2 done
    try expectContains(page, "title \"Burnup of v1\"\n");
    try expectContains(page, "  line [0, 5]\n  line [0, 2]\n");
    // a milestone whose days are not known
    try expectContains(page, "the days of 'v9' are not known");
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}
