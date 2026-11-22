//! People, calendars and load: `.skein/resources.toml`, durations in
//! working days, `skein load`, and what `check` says of them.

// req: planning.resources, planning.people, planning.calendar, planning.load, planning.overallocation
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const load_command = @import("../../commands/load.zig");

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
    \\[attributes.effort]
    \\type = "integer"
    \\[attributes.owner]
    \\list = true
    \\
    \\[planning]
    \\start = "start"
    \\finish = "finish"
    \\duration = "days"
    \\estimate = "effort"
    \\assignees = "owner"
    \\
;

const resources =
    \\[calendar]
    \\workdays = ["mon", "tue", "wed", "thu", "fri"]
    \\hours = 8
    \\holidays = [2027-03-05]
    \\
    \\[people.ann]
    \\name = "Ann Example"
    \\
    \\[people.bob]
    \\share = 0.5
    \\absent = [[2027-03-08, 2027-03-09]]
    \\
;

const Run = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8 = "",

    fn init(self: *Run, plan: []const u8, people: []const u8) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n");
        try write(dir, ".skein/types/task.toml", task_type);
        if (people.len > 0) try write(dir, ".skein/resources.toml", people);
        try write(dir, "plan/plan.md", plan);
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn check(self: *Run) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.root })).text;
    }

    fn load(self: *Run, json: bool) ![]const u8 {
        return (try load_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .json = json })).text;
    }
};

test "a duration counts working days: weekends and holidays are skipped" {
    var r: Run = undefined;
    // Monday 2027-03-01, five working days with Friday a holiday: to Monday the 8th
    try r.init("%task[t.a start=2027-03-01 days=5 finish=2027-03-05] Not with the holiday.\n\n%task[t.b start=2027-03-01 days=5 finish=2027-03-08] With it.\n", resources);
    defer r.deinit();
    const out = try r.check();
    try expectContains(out, "t.a: a start of 2027-03-01 and a duration of 5 working days finish on 2027-03-08, not 2027-03-05");
    try testing.expect(std.mem.find(u8, out, "t.b:") == null);
}

test "load: effort spread over the working days, shared among assignees, beside capacity" {
    var r: Run = undefined;
    // ann alone: 10 days of effort (80 h) over 5 working days, 16 h a day:
    // Monday to Thursday, and past the holiday and the weekend, Monday the 8th;
    // ann and bob: 2 days (16 h) over the 8th and 9th, shared
    try r.init("%task[t.a start=2027-03-01 days=5 effort=10 owner=ann] Heavy.\n\n%task[t.b start=2027-03-08 days=2 owner=ann,bob] Shared.\n", resources);
    defer r.deinit();
    const text = try r.load(false);
    try expectContains(text, "ann (Ann Example)\n  2027-W09  2027-03-01    64.0 h of  32.0 h  over by 32.0 h\n  2027-W10  2027-03-08    24.0 h of  40.0 h\n");
    // bob: half time, away Monday and Tuesday of the week of 03-08
    try expectContains(text, "bob\n  2027-W10  2027-03-08     8.0 h of  12.0 h\n");
    try expectContains(try r.load(true), "\"week\": \"2027-W09\"");

    const out = try r.check();
    try expectContains(out, "ann has 64.0 hours of work in the week of 2027-03-01 (2027-W09), and 32.0 hours to work");
    try expectContains(out, "no problems");
}

test "an assignee who is not listed, and a resources file with mistakes" {
    var r: Run = undefined;
    try r.init("%task[t.a start=2027-03-01 days=1 owner=carol] Who?\n", "[calendar]\nworkdays = [\"mon\", \"someday\"]\n[people.ann]\nshare = 0.5\nhours = 20\nabsent = [2027-03-09, [2027-03-10]]\n");
    defer r.deinit();
    const out = try r.check();
    try expectContains(out, "t.a: 'carol' is not among the people of .skein/resources.toml");
    try expectContains(out, "'someday' is no day");
    try expectContains(out, "give a share or hours a week, not both");
    try expectContains(out, "expected an array of dates and of [first, last] pairs of dates");
}

test "without a resources file: every day counts, and load says what is missing" {
    var r: Run = undefined;
    try r.init("%task[t.a start=2027-03-01 days=7 finish=2027-03-07] A week.\n", "");
    defer r.deinit();
    try expectContains(try r.check(), "no problems");
    try expectContains(try r.load(false), "the project has no .skein/resources.toml");
}
