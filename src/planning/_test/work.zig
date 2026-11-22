//! Work items: the planning roles of their types and links, and what
//! `check` holds them to before any schedule.

// req: planning.roles, planning.link-roles, planning.modes, planning.checks
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");

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

const task_type =
    \\[attributes.start]
    \\type = "date"
    \\[attributes.finish]
    \\type = "date"
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.schedule]
    \\values = ["fixed", "float"]
    \\[attributes.owner]
    \\
    \\[planning]
    \\start = "start"
    \\finish = "finish"
    \\duration = "days"
    \\mode = "schedule"
    \\assignees = "owner"
    \\
;

fn project(a: std.mem.Allocator, tmp: *testing.TmpDir, plan: []const u8) ![]const u8 {
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(tmp.dir, ".skein/types/task.toml", task_type);
    try write(tmp.dir, ".skein/types/req.toml", "");
    try write(tmp.dir, ".skein/links/precedes.toml", "from = [\"task\"]\n[planning]\nrole = \"precedes\"\n");
    try write(tmp.dir, ".skein/links/part_of.toml", "from = [\"task\"]\n[planning]\nrole = \"parent\"\n");
    try write(tmp.dir, "plan/plan.md", plan);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    return (try check_command.run(testing.io, a, .{ .root = root })).text;
}

test "work items that agree with themselves pass" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const out = try project(arena.allocator(), &tmp,
        \\%task[t.design start=2027-03-01 days=5 finish=2027-03-05 owner=ann precedes=t.build] Design.
        \\
        \\%task[t.build days=10 part_of=t.all] Build.
        \\
        \\%task[t.all schedule=float days=20] All of it.
        \\
    );
    try expectContains(out, "no problems");
}

test "check: dates against the duration, modes, loops, and what has no length" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const out = try project(arena.allocator(), &tmp,
        \\%task[t.a start=2027-03-01 days=5 finish=2027-03-09] Off by four.
        \\
        \\%task[t.b start=2027-03-10 finish=2027-03-01] Backwards.
        \\
        \\%task[t.c schedule=fixed days=3] Fixed without a start.
        \\
        \\%task[t.d precedes=t.e] No length, and followed.
        \\
        \\%task[t.e days=2 precedes=t.f] One.
        \\
        \\%task[t.f days=2 precedes=t.e] Two.
        \\
        \\%task[t.g days=1 precedes=r.one] Precedes a requirement.
        \\
        \\%req[r.one] A requirement.
        \\
    );
    try expectContains(out, "t.a: a start of 2027-03-01 and a duration of 5 working days finish on 2027-03-05, not 2027-03-09");
    try expectContains(out, "t.b: it finishes (2027-03-01) before it starts (2027-03-10)");
    try expectContains(out, "t.c: a fixed work item needs a start");
    try expectContains(out, "t.d: 't.e' follows it, and it has no duration");
    try expectContains(out, "a loop of predecessors: t.e -> t.f -> t.e");
    try expectContains(out, "t.g: precedes: 'r.one' is not a work item");
}

test "the schema: roles name attributes of the right kind, link roles are known" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(tmp.dir, ".skein/types/task.toml", "[attributes.start]\n[attributes.mode]\nvalues = [\"fixed\", \"later\"]\n[planning]\nstart = \"start\"\nduration = \"days\"\nmode = \"mode\"\nwhen = \"start\"\n");
    try write(tmp.dir, ".skein/links/precedes.toml", "[planning]\nrole = \"before\"\n");
    try write(tmp.dir, "plan/plan.md", "%task[t.a] A.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const out = (try check_command.run(testing.io, a, .{ .root = root })).text;
    try expectContains(out, "the attribute 'start' must be of type \"date\" for start");
    try expectContains(out, "there is no attribute 'days' (declare it under [attributes])");
    try expectContains(out, "the attribute 'mode' may only have the values \"fixed\" and \"float\"");
    try expectContains(out, "when");
    try expectContains(out, "expected \"precedes\", \"parent\" or \"blocks\"");
}
