//! Boards and the roadmap in a document: columns by status, assignee or
//! milestone; milestones with their dates, progress and work.

// req: render.board, render.roadmap, planning.views
const std = @import("std");
const testing = std.testing;

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

test "board and roadmap requests" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(dir, ".skein/types/task.toml",
        \\statuses = ["open", "doing", "done", "removed"]
        \\[attributes.start]
        \\type = "date"
        \\[attributes.days]
        \\type = "integer"
        \\[attributes.due]
        \\[attributes.owner]
        \\[planning]
        \\start = "start"
        \\duration = "days"
        \\milestone = "due"
        \\assignees = "owner"
        \\
    );
    try write(dir, "plan/plan.md",
        \\# Plan
        \\
        \\%task[v1 start=2027-03-12 days=0] Version 1.
        \\
        \\%task[v2 start=2027-04-30 days=0] Version 2.
        \\
        \\%task[t.a start=2027-03-01 days=3 due=v1 owner=ann done] The parser.
        \\
        \\%task[t.b start=2027-03-04 days=2 due=v1 owner=bob doing] The checker.
        \\
        \\%task[t.c start=2027-04-01 days=5 due=v2 owner=ann] The renderer.
        \\
    );
    try write(dir, "plan/views.md", "# Views\n\n```skein\nboard task\n```\n\n```skein\nboard task by=assignee\n```\n\n```skein\nroadmap\n```\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    const page = try dir.readFileAlloc(testing.io, "out/plan/views.md", a, .limited(1 << 16));
    // a column for each status but the tombstone, in order
    try expectContains(page, "| open (3) | doing (1) | done (1) |\n| --- | --- | --- |\n| [`v1`](plan.md#v1) Version 1. | [`t.b`](plan.md#t.b) The checker. | [`t.a`](plan.md#t.a) The parser. |\n");
    // by assignee: the milestones have none
    try expectContains(page, "| (unassigned) (2) | ann (2) | bob (1) |\n");
    // the roadmap: by finish, with what is done
    try expectContains(page, "| [`v1`](plan.md#v1) | 2027-03-01 | 2027-03-12 | 1 of 2 (50%) \u{2588}\u{2588}\u{2588}\u{2588}\u{2588}\u{2591}\u{2591}\u{2591}\u{2591}\u{2591} | [`t.a`](plan.md#t.a), [`t.b`](plan.md#t.b) |\n| [`v2`](plan.md#v2) | 2027-04-01 | 2027-04-30 | 0 of 1 (0%)");
}
