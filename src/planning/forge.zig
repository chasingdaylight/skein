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
const Overlay = @import("../forge/Overlay.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Work = @import("Work.zig");
const checks = @import("../forge/checks.zig");
const day = @import("day.zig");

pub const Collected = struct {
    works: []Work,
    /// the issues the forge and its cache could not say anything of
    unlearned: usize = 0,
    why: []const u8 = "",
    /// what is wrong with the overlay: a deviation whose upstream value has
    /// changed since, or of an issue no work item names
    overlay_problems: []const []const u8 = &.{},
};

pub fn collect(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, offline: bool) !Collected {
    const works = try Work.collectAll(arena, project, graph);
    var out: Collected = .{ .works = works };
    var targets: std.ArrayList([]const u8) = .empty;
    for (works) |w| if (w.issue) |i| try targets.append(arena, i);
    if (targets.items.len == 0) return out;
    const known = try checks.learnRefs(io, arena, root, project, targets.items, offline) orelse return out;
    out.why = known.why;
    var ignored: Report = .{ .arena = arena };
    const overlay = try Overlay.load(io, arena, root, &ignored);
    var problems: std.ArrayList([]const u8) = .empty;
    for (works) |*w| {
        const target = w.issue orelse continue;
        const answer = try known.of(arena, target) orelse {
            out.unlearned += 1;
            continue;
        };
        var issue = switch (answer) {
            .found => |i| i,
            else => continue,
        };
        // the what-if plan's deviations from what the forge says
        if (try Overlay.canonical(arena, &known.forge, target)) |key| {
            for (std.enums.values(Overlay.Field)) |field| {
                if (overlay.get(key, field)) |o| {
                    const now = try Overlay.upstream(arena, issue, field);
                    if (!std.mem.eql(u8, o.base, now)) {
                        try problems.append(arena, try arena.print("the overlay changes {t} of {s} from '{s}' to '{s}', and the forge now says '{s}'", .{ field, key, o.base, o.value, now }));
                    }
                    switch (field) {
                        .assignees => issue.assignees = if (o.value.len == 0) &.{} else try splitLogins(arena, o.value),
                        .milestone => {
                            issue.milestone = if (o.value.len == 0) null else o.value;
                            issue.due = null;
                        },
                        .state => issue.open = !std.mem.eql(u8, o.value, "closed"),
                    }
                }
            }
        }
        if (w.assignees.len == 0) {
            w.assignees = issue.assignees;
        } else if (!sameSet(w.assignees, issue.assignees)) w.conflict = "assignees";
        if (w.milestone == null) w.milestone = issue.milestone;
        if (issue.due) |d| w.forge_due = day.parse(d);
        if (!issue.open) w.done = true;
    }
    // a deviation of an issue no work item names
    for (overlay.entries.items) |e| {
        const named = for (works) |w| {
            const t = w.issue orelse continue;
            if (try Overlay.canonical(arena, &known.forge, t)) |key| if (std.mem.eql(u8, key, e.issue)) break true;
        } else false;
        if (!named) try problems.append(arena, try arena.print("the overlay changes {t} of {s}, which no work item is", .{ e.field, e.issue }));
    }
    out.overlay_problems = problems.items;
    return out;
}

fn splitLogins(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, text, ',');
    while (it.next()) |w| try list.append(arena, w);
    return list.items;
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
