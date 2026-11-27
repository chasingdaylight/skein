//! A baseline of a plan that takes values from the forge: they are frozen in
//! a commit the baseline tags, and an edition of it reads them, not the
//! forge as it is later. The forge is a stand-in.

// req: baselines
const std = @import("std");
const testing = std.testing;

const Forge = @import("../../forge/Forge.zig");
const Repo = @import("Repo.zig");
const Workspace = @import("../Workspace.zig");
const checks = @import("../../forge/checks.zig");
const github = @import("../../forge/github.zig");
const history = @import("../../history.zig");
const planning_forge = @import("../../planning/forge.zig");

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

var later = false;

/// #1 in milestone v1, due 2027-03-12, assigned to ann; later in v2, due
/// in June, assigned to bob. #2 closed. #3 the forge cannot say anything of.
fn fake(_: std.Io, _: std.mem.Allocator, _: *const Forge, r: Forge.Ref) anyerror!github.Answer {
    return switch (r.number) {
        1 => if (later)
            .{ .found = .{ .title = "Parser", .open = true, .pull = false, .assignees = &.{"bob"}, .milestone = "v2", .due = "2027-06-30" } }
        else
            .{ .found = .{ .title = "Parser", .open = true, .pull = false, .assignees = &.{"ann"}, .milestone = "v1", .due = "2027-03-12" } },
        2 => .{ .found = .{ .title = "Checker", .open = false, .pull = false } },
        else => .{ .unreachable_ = "no network" },
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

test "a baseline freezes the forge's values its plan uses, and an edition reads them" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.write(".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"plan\"\n[forge]\nrepository = \"example/plan\"\n");
    try repo.write(".skein/types/task.toml", task_type);
    try repo.write("plan/plan.md", "%task[t.parser days=3 issue=#1] The parser.\n\n%task[t.checker days=2 issue=#2] The checker.\n\n%task[t.gone days=1 issue=#3] Its issue cannot be had.\n");
    try repo.commit("a plan on the forge");
    const saved = checks.lookup;
    defer checks.lookup = saved;
    checks.lookup = fake;
    later = false;

    const out = try repo.baseline("v1", "As reviewed.");
    if (!out.ok) std.debug.print("{s}\n", .{out.text});
    try testing.expect(out.ok);
    try has(out.text, "skein: the forge's values of 2 issues frozen in .skein/baselines/v1.toml\n");
    try has(out.text, "skein: 1 issue the forge could say nothing of: not frozen\n");
    // the tag is of the commit that froze them
    try has(try repo.gitOutput(&.{ "log", "-1", "--format=%s", "v1" }), "Baseline v1: the forge's values its plan uses");
    const file = try repo.gitOutput(&.{ "show", "v1:.skein/baselines/v1.toml" });
    try has(file, "[\"example/plan#1\"]\nopen = true\nassignees = [\"ann\"]\nmilestone = \"v1\"\ndue = \"2027-03-12\"\n");
    try has(file, "[\"example/plan#2\"]\nopen = false\n");

    // the forge changes; the edition of v1 still has what it said then
    later = true;
    var snap = try history.snapshot(testing.io, a, repo.tmp.dir, "v1");
    defer snap.deinit();
    var old = switch (try Workspace.open(testing.io, a, .{ .root = snap.path, .offline = true, .baseline = "v1" })) {
        .ok => |w| w,
        .failed => return error.TestUnexpectedResult,
    };
    defer old.close();
    const then = (try planning_forge.collect(testing.io, a, old.root, &old.project, &old.graph, true)).works;
    for (then) |w| {
        if (std.mem.eql(u8, w.id, "t.parser")) {
            try testing.expectEqualStrings("v1", w.milestone.?);
            try testing.expectEqualStrings("ann", w.assignees[0]);
        }
        if (std.mem.eql(u8, w.id, "t.checker")) try testing.expect(w.done);
    }
    // the project as it is now asks the forge
    var now = switch (try Workspace.open(testing.io, a, .{ .root = repo.root })) {
        .ok => |w| w,
        .failed => return error.TestUnexpectedResult,
    };
    defer now.close();
    for ((try planning_forge.collect(testing.io, a, now.root, &now.project, &now.graph, false)).works) |w| {
        if (std.mem.eql(u8, w.id, "t.parser")) try testing.expectEqualStrings("v2", w.milestone.?);
    }
}
