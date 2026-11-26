//! `skein level`: work moved later until nobody has more work than time,
//! listed, and written into the work items.

// req: planning.level
const std = @import("std");
const testing = std.testing;

const check_command = @import("../check.zig");
const level_command = @import("../level.zig");

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

test "overallocated work moved later, and the moves written" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(dir, ".skein/types/task.toml",
        \\[attributes.start]
        \\type = "date"
        \\[attributes.days]
        \\type = "integer"
        \\[attributes.wait]
        \\type = "integer"
        \\[attributes.owner]
        \\list = true
        \\
        \\[planning]
        \\start = "start"
        \\duration = "days"
        \\lag = "wait"
        \\assignees = "owner"
        \\
    );
    try write(dir, ".skein/links/after.toml", "[planning]\nrole = \"follows\"\n");
    try write(dir, ".skein/resources.toml", "[calendar]\nworkdays = [\"mon\", \"tue\", \"wed\", \"thu\", \"fri\"]\nhours = 8\n\n[people.ann]\n\n[people.bob]\n");
    // a and b are both Ann's in the week of 2027-03-01; c follows b, which
    // makes b critical, so a moves; d is Bob's
    try write(dir, "plan/work.md",
        \\%task[t.a start=2027-03-01 days=5 owner=ann] First.
        \\
        \\%task[t.b start=2027-03-01 days=5 owner=ann] Second.
        \\
        \\%task[t.c days=2 owner=ann after=t.b] After the second.
        \\
        \\%task[t.d start=2027-03-01 days=5 owner=bob] Bob's.
        \\
    );
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "ann: in the week of 2027-03-01 (2027-W09), 80.0 hours of work and 40.0 hours to work");

    const proposed = (try level_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(proposed, "t.a: 2027-03-08 to 2027-03-12, from 2027-03-01 (start = 2027-03-08)\n");
    // c follows b, which stays, but Ann has a in the week after it
    try expectContains(proposed, "t.c: 2027-03-15 to 2027-03-16, from 2027-03-08 (lag = 5)\n");
    try expectContains(proposed, "nothing written");
    try testing.expect(std.mem.find(u8, proposed, "t.b:") == null);
    try testing.expect(std.mem.find(u8, proposed, "t.d:") == null);

    const done = (try level_command.run(testing.io, a, .{ .common = .{ .root = root }, .write = true })).text;
    try expectContains(done, "wrote the moves into 2 work items");
    const plan = try dir.readFileAlloc(testing.io, "plan/work.md", a, .limited(1 << 16));
    try expectContains(plan, "%task[t.a start=2027-03-08 days=5 owner=ann] First.");
    try expectContains(plan, "%task[t.c days=2 owner=ann after=t.b wait=5] After the second.");
    try testing.expect(std.mem.find(u8, (try check_command.run(testing.io, a, .{ .root = root })).text, "hours to work") == null);
    try expectContains((try level_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "nothing to move");
}

test "a float item that follows others waits longer, by its lag" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
    try write(dir, ".skein/types/task.toml", "[attributes.start]\ntype = \"date\"\n[attributes.days]\ntype = \"integer\"\n[attributes.wait]\ntype = \"integer\"\n[attributes.owner]\nlist = true\n\n[planning]\nstart = \"start\"\nduration = \"days\"\nlag = \"wait\"\nassignees = \"owner\"\n");
    try write(dir, ".skein/links/after.toml", "[planning]\nrole = \"follows\"\n");
    try write(dir, ".skein/resources.toml", "[calendar]\nworkdays = [\"mon\", \"tue\", \"wed\", \"thu\", \"fri\"]\nhours = 8\n\n[people.ann]\n");
    // t.y follows t.x and falls in the week Ann has t.z
    try write(dir, "plan/work.md",
        \\%task[t.x start=2027-03-01 days=1 owner=bob] Bob's day.
        \\
        \\%task[t.z start=2027-03-01 days=5 owner=ann] Ann's week.
        \\
        \\%task[t.y days=1 owner=ann after=t.x] Ann's day after Bob's.
        \\
    );
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const done = (try level_command.run(testing.io, a, .{ .common = .{ .root = root }, .write = true })).text;
    try expectContains(done, "t.y: 2027-03-08 to 2027-03-08, from 2027-03-02 (lag = 4)\n");
    try expectContains(try dir.readFileAlloc(testing.io, "plan/work.md", a, .limited(1 << 16)), "%task[t.y days=1 owner=ann after=t.x wait=4]");
}
