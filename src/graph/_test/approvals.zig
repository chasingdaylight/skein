//! Approvals, on a project on disk.

// req: approval.record, approval.records, approval.current, approval.status
// req: check.schema-first, principle.plain-text
const std = @import("std");
const testing = std.testing;

const approve_command = @import("../../commands/approve.zig");
const check_command = @import("../../commands/check.zig");
const trace_command = @import("../../commands/trace.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

/// Requirements whose status `approved` needs an approval
fn project(dir: std.Io.Dir) !void {
    try write(dir, ".skein/config.toml",
        \\[project]
        \\name = "example"
        \\[[sources]]
        \\path = "requirements"
        \\kind = "items"
        \\type = "srs"
        \\[[sources]]
        \\path = "spec"
    );
    try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\napproval = [\"approved\"]\n");
    try write(dir, ".skein/types/rule.toml", "approval = [\"approved\"]\n");
    try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\nstatus = \"approved\"\n+++\nThe software shall start.\n");
    try write(dir, "requirements/SRS-002.md", "+++\nid = \"SRS-002\"\n+++\nA draft needs no approval.\n");
    try write(dir, "spec/a.md", "rule[a.rule] status=approved\nA rule.\n");
}

const Run = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Run) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.root = try self.tmp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn check(self: *Run) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.root })).text;
    }

    fn approve(self: *Run, ids: []const []const u8, by: ?[]const u8, on: ?[]const u8) ![]const u8 {
        return (try approve_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .ids = ids, .by = by, .on = on })).text;
    }

    fn read(self: *Run, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }
};

test "a status that needs an approval is reported until the item is approved" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);

    try testing.expectEqualStrings(
        \\requirements/SRS-001.md:1:1: error: SRS-001: the status 'approved' needs an approval, and the item has none ('skein approve SRS-001')
        \\spec/a.md:1:1: error: a.rule: the status 'approved' needs an approval, and the item has none ('skein approve a.rule')
        \\skein: 2 problems
        \\
    , try run.check());

    try testing.expectEqualStrings(
        "skein: 2 items approved by A. Reviewer on 2027-03-01\n",
        try run.approve(&.{ "SRS-001", "a.rule" }, "A. Reviewer", "2027-03-01"),
    );
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));
}

test "approvals are kept by document and by directory, one line per item and approver" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    _ = try run.approve(&.{ "SRS-001", "SRS-002", "a.rule" }, "B. \"Quoted\" Name", "2027-03-02");
    _ = try run.approve(&.{"SRS-001"}, "A. Reviewer", "2027-03-01");
    // approving again replaces that person's record
    _ = try run.approve(&.{"SRS-001"}, "A. Reviewer", "2027-03-05");

    const by_directory = try run.read(".skein/approvals/requirements.toml");
    var lines = std.mem.splitScalar(u8, by_directory, '\n');
    try testing.expectEqualStrings("# Approvals, written by skein. Do not edit: use 'skein approve'.", lines.next().?);
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "\"SRS-001\".\"A. Reviewer\" = { on = 2027-03-05, fingerprint = \""));
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "\"SRS-001\".\"B. \\\"Quoted\\\" Name\" = { on = 2027-03-02, fingerprint = \""));
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "\"SRS-002\".\"B. \\\"Quoted\\\" Name\" = { on = 2027-03-02, fingerprint = \""));
    try testing.expectEqualStrings("", lines.next().?);
    try testing.expectEqual(null, lines.next());
    try testing.expect(std.mem.find(u8, try run.read(".skein/approvals/spec/a.md.toml"), "\"a.rule\".") != null);
    // what was written reads back
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));
}

test "a changed item is no longer approved; one laid out anew still is" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    _ = try run.approve(&.{ "SRS-001", "a.rule" }, "A. Reviewer", "2027-03-01");

    try write(run.tmp.dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\nstatus = \"approved\"\n+++\r\nThe software\r\nshall   start.\r\n");
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));

    try write(run.tmp.dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\nstatus = \"approved\"\n+++\nThe software shall start within a second.\n");
    try testing.expectEqualStrings(
        \\requirements/SRS-001.md:1:1: error: SRS-001: the item has changed since A. Reviewer approved it, and the status 'approved' needs an approval ('skein approve SRS-001')
        \\skein: 1 problem
        \\
    , try run.check());

    // trace shows what the record is of
    const traced = (try trace_command.run(testing.io, run.arena.allocator(), .{ .common = .{ .root = run.root }, .id = "SRS-001" })).text;
    try testing.expect(std.mem.find(u8, traced, "\nApproved by:\n  A. Reviewer on 2027-03-01  [of an earlier version]\n") != null);
    const current = (try trace_command.run(testing.io, run.arena.allocator(), .{ .common = .{ .root = run.root }, .id = "a.rule" })).text;
    try testing.expect(std.mem.find(u8, current, "\nApproved by:\n  A. Reviewer on 2027-03-01\n") != null);
}

test "who and when: a date that is none, an item that is none" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    try testing.expectEqualStrings("skein: '1 March' is no date; write it like 2027-03-01\n", try run.approve(&.{"SRS-001"}, "A. Reviewer", "1 March"));
    try testing.expectEqualStrings("skein: there is no item 'SRS-999'\n", try run.approve(&.{"SRS-999"}, "A. Reviewer", null));
    // without --on, the date is today's
    try testing.expect(std.mem.startsWith(u8, try run.approve(&.{"SRS-001"}, "A. Reviewer", null), "skein: 1 item approved by A. Reviewer on 20"));
}

test "a status that needs approval must be one of the statuses" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "");
    try write(tmp.dir, ".skein/types/srs.toml", "approval = [\"signed\"]\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());
    const text = (try check_command.run(testing.io, arena.allocator(), .{ .root = root })).text;
    try testing.expectEqualStrings(
        \\.skein/types/srs.toml: error: approval: 'signed' is not one of the statuses
        \\skein: 1 problem
        \\
    , text);
}
