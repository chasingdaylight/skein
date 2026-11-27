//! Work items that are issues on the forge: their assignees, milestone and
//! its due day, and state are the forge's, read through the adapter, which
//! the test stands in for.

// req: planning.forge-fields, planning.forge
const std = @import("std");
const testing = std.testing;

const Forge = @import("../../forge/Forge.zig");
const check_command = @import("../../commands/check.zig");
const checks = @import("../../forge/checks.zig");
const git_program = @import("../../git.zig");
const github = @import("../../forge/github.zig");
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

var reachable = true;

/// #1: open, assigned to ann, in milestone v1 due 2027-03-12; #2: closed,
/// assigned to bob, no milestone
fn fake(_: std.Io, _: std.mem.Allocator, _: *const Forge, r: Forge.Ref) anyerror!github.Answer {
    if (!reachable) return .{ .unreachable_ = "no network" };
    return switch (r.number) {
        1 => .{ .found = .{ .title = "Parser", .open = true, .pull = false, .assignees = &.{"ann"}, .milestone = "v1", .due = "2027-03-12" } },
        2 => .{ .found = .{ .title = "Checker", .open = false, .pull = false, .assignees = &.{"bob"} } },
        else => .missing,
    };
}

const task_type =
    \\statuses = ["open", "done"]
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.owner]
    \\[attributes.due]
    \\[attributes.issue]
    \\[planning]
    \\duration = "days"
    \\assignees = "owner"
    \\milestone = "due"
    \\issue = "issue"
    \\
;

test "work that is an issue: assignees, a due day for its finish, closed as done, all the forge's" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    _ = try git_program.output(testing.io, a, dir, &.{ "init", "--quiet" });
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n\n[forge]\nrepository = \"example/plan\"\n");
    try write(dir, ".skein/types/task.toml", task_type);
    try write(dir, ".skein/resources.toml", "[people.ann]\n[people.bob]\n");
    // the milestone is a work item too, which the board and roadmap name
    try write(dir, "plan/plan.md",
        \\%task[v1 days=0] Version 1.
        \\
        \\%task[t.parser days=3 issue=#1] The parser.
        \\
        \\%task[t.checker days=2 issue=#2] The checker.
        \\
        \\%task[t.wrong days=1 issue=#1 owner=carol] Says otherwise of its issue.
        \\
    );
    try write(dir, "plan/views.md", "# Views\n\n```skein\nroadmap v1\n```\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const saved = checks.lookup;
    defer checks.lookup = saved;
    checks.lookup = fake;
    reachable = true;

    // the schedule: the parser finishes when its milestone is due, three working days
    const said = (try schedule_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(said, "work items scheduled");
    const toml = try dir.readFileAlloc(testing.io, ".skein/schedule.toml", a, .limited(1 << 16));
    try expectContains(toml, "[items.\"t.parser\"]\nstart = 2027-03-10\nfinish = 2027-03-12\nmode = \"float\"\nsource = \"forge\"\n");

    // the forge's assignees are known without being written: ann and bob are people
    const out = (try check_command.run(testing.io, a, .{ .root = root })).text;
    try expectContains(out, "t.wrong: it writes assignees that its issue #1 on the forge says otherwise of");
    try expectContains(out, "t.wrong: 'carol' is not among the people");

    // the roadmap: the closed issue is done work, in the milestone the forge names
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir });
    const page = try dir.readFileAlloc(testing.io, "out/plan/views.md", a, .limited(1 << 16));
    try expectContains(page, "| [`v1`](plan.md#v1) | 2027-03-10 | ");

    // offline, with the forge out of reach and no cache of an issue it has not been asked of
    reachable = false;
    try write(dir, "plan/plan.md", "%task[t.new days=1 issue=#7] A new one.\n");
    const offline = (try check_command.run(testing.io, a, .{ .root = root, .offline = true })).text;
    try expectContains(offline, "the stored schedule is not checked: 1 issue of work items could not be learned from the forge");
}
