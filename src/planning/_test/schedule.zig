//! The schedule: float items from their predecessors and parents, slack
//! and the critical path, `skein schedule` and the stored files, and what
//! `check` holds the schedule to.

// req: planning.schedule, planning.critical-path, planning.stored, planning.schedule-checks
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
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

const task_type =
    \\[attributes.start]
    \\type = "date"
    \\[attributes.finish]
    \\type = "date"
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.wait]
    \\type = "integer"
    \\[attributes.mode]
    \\[attributes.due]
    \\
    \\[planning]
    \\start = "start"
    \\finish = "finish"
    \\duration = "days"
    \\lag = "wait"
    \\mode = "mode"
    \\milestone = "due"
    \\
;

const Run = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8 = "",

    fn init(self: *Run, config: []const u8, text: []const u8) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml", config);
        try write(dir, ".skein/types/task.toml", task_type);
        try write(dir, ".skein/links/precedes.toml", "[planning]\nrole = \"precedes\"\n");
        try write(dir, ".skein/links/part_of.toml", "[planning]\nrole = \"parent\"\n");
        // Monday to Friday
        try write(dir, ".skein/resources.toml", "[calendar]\n");
        try write(dir, "plan/plan.md", text);
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn check(self: *Run) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.root })).text;
    }

    fn schedule(self: *Run) ![]const u8 {
        return (try schedule_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root } })).text;
    }

    fn read(self: *Run, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }
};

const plan =
    \\%task[t.all] All of it, spanning its parts.
    \\
    \\%task[t.design start=2027-03-01 days=5 part_of=t.all precedes=t.build,t.docs] Design, fixed.
    \\
    \\%task[t.build days=3 part_of=t.all precedes=t.test] Build, after the design.
    \\
    \\%task[t.test days=2 part_of=t.all precedes=t.ship] Test.
    \\
    \\%task[t.docs days=1 part_of=t.all] Documentation, with slack.
    \\
    \\%task[t.ship days=1 wait=2 part_of=t.all] Ship, two working days after the tests.
    \\
;

test "skein schedule: float work after its predecessors, parents spanning their children, the critical path" {
    var r: Run = undefined;
    try r.init("[[sources]]\npath = \"plan\"\n[schedule]\nalso = [\"json\", \"csv\"]\n", plan);
    defer r.deinit();
    // before it is run, check asks for it
    try expectContains(try r.check(), ".skein/schedule.toml: error: there is no stored schedule of the work items here: run 'skein schedule'");

    const said = try r.schedule();
    try expectContains(said, "skein: 6 work items scheduled, 5 on the critical path; wrote .skein/schedule.toml, .skein/schedule.json, .skein/schedule.csv");
    try expectContains(said, "wrote the mode float into 5 items");
    const toml = try r.read(".skein/schedule.toml");
    // the design's finish is Friday; the build starts the Monday after
    try expectContains(toml, "[items.\"t.build\"]\nstart = 2027-03-08\nfinish = 2027-03-10\nmode = \"float\"\nsource = \"computed\"\nslack = 0\ncritical = true\n");
    try expectContains(toml, "[items.\"t.design\"]\nstart = 2027-03-01\nfinish = 2027-03-05\nmode = \"fixed\"\nsource = \"written\"\nslack = 0\ncritical = true\n");
    // two working days of lag after the tests finish on Friday the 12th
    try expectContains(toml, "[items.\"t.ship\"]\nstart = 2027-03-17\nfinish = 2027-03-17\n");
    // the documentation can slip seven working days, to the end of the plan
    try expectContains(toml, "[items.\"t.docs\"]\nstart = 2027-03-08\nfinish = 2027-03-08\nmode = \"float\"\nsource = \"computed\"\nslack = 7\ncritical = false\n");
    try expectContains(toml, "[items.\"t.all\"]\nstart = 2027-03-01\nfinish = 2027-03-17\n");
    try expectContains(try r.read(".skein/schedule.json"), "\"id\": \"t.docs\"");
    try expectContains(try r.read(".skein/schedule.csv"), "t.docs,2027-03-08,2027-03-08,float,computed,7,false\n");
    // the mode is written into the items that named none
    try expectContains(try r.read("plan/plan.md"), "%task[t.build days=3 part_of=t.all precedes=t.test mode=float]");

    // now it is current; a change to the plan makes it out of date
    try expectContains(try r.check(), "no problems");
    try write(r.tmp.dir, "plan/plan.md", try std.mem.replaceOwned(u8, r.arena.allocator(), try r.read("plan/plan.md"), "t.build days=3", "t.build days=4"));
    const stale = try r.check();
    try expectContains(stale, ".skein/schedule.toml: error: the stored schedule is not the one the work items give now: run 'skein schedule'");
    try expectContains(stale, ".skein/schedule.csv: error: the stored schedule is not the one");
}

test "check: before the predecessors, outside the parent, after the milestone, nothing to schedule from" {
    var r: Run = undefined;
    try r.init("[[sources]]\npath = \"plan\"\n",
        \\%task[t.design start=2027-03-01 days=5 precedes=t.late] Design.
        \\
        \\%task[t.late start=2027-03-03 days=1] Starts too early.
        \\
        \\%task[t.phase start=2027-03-01 finish=2027-03-02] A short phase.
        \\
        \\%task[t.inner start=2027-03-01 days=5 part_of=t.phase] Longer than its phase.
        \\
        \\%task[t.gate start=2027-03-04 days=0] A milestone.
        \\
        \\%task[t.work start=2027-03-01 days=5 due=t.gate] Due at the gate.
        \\
        \\%task[t.alone days=1] Nothing to schedule it from.
        \\
    );
    defer r.deinit();
    _ = try r.schedule();
    const out = try r.check();
    try expectContains(out, "t.late: it starts on 2027-03-03, and its predecessors let it start on 2027-03-08 at the earliest");
    try expectContains(out, "t.inner: it runs from 2027-03-01 to 2027-03-05, outside its parent t.phase (2027-03-01 to 2027-03-02)");
    try expectContains(out, "t.work: it finishes on 2027-03-05, after its milestone t.gate (2027-03-04)");
    try expectContains(out, "warning: t.alone: it cannot be scheduled");
}
