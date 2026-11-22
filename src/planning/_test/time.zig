//! Time spent on work items: logging with `skein time`, the report of
//! spent against estimate, the `time` request, and what `check` says.

// req: planning.time, planning.time-report
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const render_command = @import("../../commands/render.zig");
const time_command = @import("../../commands/time.zig");

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

test "time is logged, reported against the estimate, and shown in a document" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(dir, ".skein/types/task.toml", "[attributes.days]\ntype = \"integer\"\n[attributes.effort]\ntype = \"integer\"\n[planning]\nduration = \"days\"\nestimate = \"effort\"\n");
    try write(dir, ".skein/resources.toml", "[calendar]\nhours = 6\n");
    try write(dir, "plan/plan.md", "%task[t.a days=3 effort=2] Has an estimate of two days.\n\n%task[t.b days=1] Has none.\n\n%task[t.c days=1 effort=1] Nothing spent.\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const common: @import("../../cli.zig").Common = .{ .root = root };

    const first = (try time_command.run(testing.io, a, .{ .common = common, .id = "t.a", .hours = "5", .by = "ann", .on = "2027-03-02", .note = "first pass" })).text;
    try expectContains(first, "skein: t.a has 5 hours of ann on 2027-03-02, in .skein/time/plan/plan.md.toml\n");
    // the same day again adds to it
    try expectContains((try time_command.run(testing.io, a, .{ .common = common, .id = "t.a", .hours = "2.5", .by = "ann", .on = "2027-03-02" })).text, "has 7.5 hours");
    _ = try time_command.run(testing.io, a, .{ .common = common, .id = "t.a", .hours = "6", .by = "bob", .on = "2027-03-03" });
    _ = try time_command.run(testing.io, a, .{ .common = common, .id = "t.b", .hours = "1", .by = "ann", .on = "2027-03-03" });
    const file = try dir.readFileAlloc(testing.io, ".skein/time/plan/plan.md.toml", a, .limited(1 << 16));
    try expectContains(file, "\"t.a\".\"ann\".\"2027-03-02\" = { hours = 7.5, note = \"first pass\" }\n\"t.a\".\"bob\".\"2027-03-03\" = { hours = 6 }\n");

    // what is refused
    try expectContains((try time_command.run(testing.io, a, .{ .common = common, .id = "t.a", .hours = "20", .by = "ann", .on = "2027-03-02" })).text, "that makes 27.5 hours on 2027-03-02");
    try expectContains((try time_command.run(testing.io, a, .{ .common = common, .id = "t.a", .hours = "0", .by = "ann" })).text, "hours are more than 0");
    try expectContains((try time_command.run(testing.io, a, .{ .common = common, .id = "nope", .hours = "1", .by = "ann" })).text, "there is no item 'nope'");

    // the report, in the calendar's 6-hour days: t.a is estimated at 12 hours
    const report = (try time_command.run(testing.io, a, .{ .common = common })).text;
    try expectContains(report, "t.a  estimate 12.0 h  spent 13.5 h  (+1.5 h)  by ann 7.5, bob 6.0\n");
    try expectContains(report, "t.b  no estimate    spent 1.0 h  by ann 1.0\n");
    try expectContains(report, "t.c  estimate 6.0 h  spent 0.0 h  (-6.0 h)\n");
    try expectContains(report, "In all: estimate 18.0 h, spent 14.5 h\n");
    try expectContains((try time_command.run(testing.io, a, .{ .common = common, .json = true })).text, "\"item\": \"t.a\"");

    // in a document
    try write(dir, "plan/report.md", "# Time\n\n```skein\ntime task\n```\n");
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = common, .out = out_dir });
    const page = try dir.readFileAlloc(testing.io, "out/plan/report.md", a, .limited(1 << 16));
    try expectContains(page, "| [`t.a`](plan.md#t.a) | 12.0 | 13.5 | +1.5 | ann 7.5, bob 6.0 |\n");
    try expectContains(page, "| **In all** | 18.0 | 14.5 | -3.5 | |\n");

    // check: time on what is no work item
    try write(dir, ".skein/time/plan/plan.md.toml", "\"t.gone\".\"ann\".\"2027-03-02\" = { hours = 2 }\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "time of ann on 2027-03-02: 't.gone' is no work item");
}
