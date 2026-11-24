//! The Gantt chart a document asks for: bars, milestones and the critical
//! path as a Mermaid diagram, sections by parent or assignee, a baseline's
//! bars beside today's, and the table of dates under it.

// req: render.gantt
const std = @import("std");
const testing = std.testing;

const git_program = @import("../../git.zig");
const render_command = @import("../../commands/render.zig");
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

fn commit(a: std.mem.Allocator, dir: std.Io.Dir) !void {
    _ = try git_program.output(testing.io, a, dir, &.{ "add", "--all" });
    _ = try git_program.output(testing.io, a, dir, &.{ "-c", "user.name=A. Author", "-c", "user.email=a@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "change" });
}

const task_type =
    \\[attributes.start]
    \\type = "date"
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.owner]
    \\[planning]
    \\start = "start"
    \\duration = "days"
    \\assignees = "owner"
    \\
;

const plan =
    \\# Plan
    \\
    \\%task[t.all] The release.
    \\
    \\%task[t.design start=2027-03-01 days=5 part_of=t.all precedes=t.build,t.docs owner=ann] Design.
    \\
    \\%task[t.build days=3 part_of=t.all precedes=t.gate owner=bob] Build.
    \\
    \\%task[t.docs days=1 part_of=t.all owner=ann] Documentation.
    \\
    \\%task[t.gate days=0] Release.
    \\
;

test "a gantt request: the chart, its sections, the critical path, a baseline's bars" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "init", "--quiet" });
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(tmp.dir, ".skein/types/task.toml", task_type);
    try write(tmp.dir, ".skein/links/precedes.toml", "[planning]\nrole = \"precedes\"\n");
    try write(tmp.dir, ".skein/links/part_of.toml", "[planning]\nrole = \"parent\"\n");
    try write(tmp.dir, ".skein/resources.toml", "[calendar]\nholidays = [2027-03-10]\n");
    try write(tmp.dir, "plan/plan.md", plan);
    try write(tmp.dir, "plan/chart.md", "# Chart\n\n```skein\ngantt task\n```\n\n```skein\ngantt task by=assignee baseline=b1\n```\n\n```skein\ngantt task baseline=none\n```\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    _ = try schedule_command.run(testing.io, a, .{ .common = .{ .root = root } });
    try commit(a, tmp.dir);
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "tag", "b1" });
    // the build takes a day more since the baseline
    try write(tmp.dir, "plan/plan.md", try std.mem.replaceOwned(u8, a, try tmp.dir.readFileAlloc(testing.io, "plan/plan.md", a, .limited(1 << 16)), "t.build days=3", "t.build days=4"));

    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir })).status);
    const chart = try tmp.dir.readFileAlloc(testing.io, "out/plan/chart.md", a, .limited(1 << 16));
    // weekends and the holiday are left out; the parent is a section of its parts
    try expectContains(chart, "```mermaid\ngantt\n  dateFormat YYYY-MM-DD\n  excludes weekends, 2027-03-10\n  section t.all\n  t.all :t1, 2027-03-01, 2027-03-13\n  t.design :crit, t2, 2027-03-01, 2027-03-06\n");
    // the build: Monday the 8th, past the holiday, four working days
    try expectContains(chart, "  t.build :crit, t3, 2027-03-08, 2027-03-13\n  t.docs :t4, 2027-03-08, 2027-03-09\n  section Work\n  t.gate :milestone, t5, 2027-03-15, 0d\n```");
    try expectContains(chart, "| [`t.docs`](plan.md#t.docs) | 2027-03-08 | 2027-03-08 | 4 | [`t.design`](plan.md#t.design) |");
    try expectContains(chart, "| [`t.build`](plan.md#t.build) | 2027-03-08 | 2027-03-12 | **critical** 0 |");
    // by assignee, with the baseline's bars: the build was a day shorter then
    try expectContains(chart, "  section ann\n  t.design :crit, t1, 2027-03-01, 2027-03-06\n  t.design at b1 :done, t2, 2027-03-01, 2027-03-06\n");
    try expectContains(chart, "  section bob\n  t.build :crit, t5, 2027-03-08, 2027-03-13\n  t.build at b1 :done, t6, 2027-03-08, 2027-03-12\n");
    try expectContains(chart, "  section Unassigned\n");
    try expectContains(chart, "> **skein:** there is no schedule stored at the baseline 'none'");
}
