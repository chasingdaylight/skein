//! The work items with what the forge holds of their issues (planning role
//! `issue`): GitHub stores assignees, a milestone with its due day, and
//! whether the issue is closed; not a start, a duration or effort, which
//! stay in the items (design 10.4). The forge is the truth for what it
//! holds: the item need not write it, and an item that writes assignees the
//! forge says otherwise of is reported. A closed issue is finished work. The
//! forge is asked unless offline; what it last said is kept, and used when
//! it cannot be reached.

const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Work = @import("Work.zig");
const checks = @import("../forge/checks.zig");
const day = @import("day.zig");

pub const Collected = struct {
    works: []Work,
    /// the issues the forge and its cache could not say anything of
    unlearned: usize = 0,
    why: []const u8 = "",
};

pub fn collect(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, offline: bool) !Collected {
    const works = try Work.collect(arena, &project.schema, graph);
    var out: Collected = .{ .works = works };
    var targets: std.ArrayList([]const u8) = .empty;
    for (works) |w| if (w.issue) |i| try targets.append(arena, i);
    if (targets.items.len == 0) return out;
    const known = try checks.learnRefs(io, arena, root, project, targets.items, offline) orelse return out;
    out.why = known.why;
    for (works) |*w| {
        const target = w.issue orelse continue;
        const answer = try known.of(arena, target) orelse {
            out.unlearned += 1;
            continue;
        };
        const issue = switch (answer) {
            .found => |i| i,
            else => continue,
        };
        if (w.assignees.len == 0) {
            w.assignees = issue.assignees;
        } else if (!sameSet(w.assignees, issue.assignees)) w.conflict = "assignees";
        if (w.milestone == null) w.milestone = issue.milestone;
        if (issue.due) |d| w.forge_due = day.parse(d);
        if (!issue.open) w.done = true;
    }
    return out;
}

fn sameSet(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a) |x| {
        for (b) |y| {
            if (std.mem.eql(u8, x, y)) break;
        } else return false;
    }
    return true;
}
