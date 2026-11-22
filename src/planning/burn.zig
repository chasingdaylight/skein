//! What burndown and burnup charts draw: for a milestone, day by day, the
//! work in it (its scope) and the work done, counted in items or in weight
//! (an item's estimate, else its duration). Each day is the project as it
//! was committed at the end of that day, on the first-parent history of
//! the checkout, so work added to or taken out of the milestone shows as a
//! change of scope, as GitLab's charts show it; today is the files as they
//! are. Nothing is recorded by hand.

const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");

pub const Point = struct { day: day.Day, total: f64, done: f64 };

pub const Count = enum { items, weight };

/// The work of `milestone` in a project, and how much of it is done
pub fn measure(arena: std.mem.Allocator, project: *const Project, graph: *const Graph, milestone: []const u8, count: Count) std.mem.Allocator.Error!struct { total: f64, done: f64 } {
    var total: f64 = 0;
    var done: f64 = 0;
    for (try Work.collect(arena, &project.schema, graph)) |*w| {
        const m = w.milestone orelse continue;
        if (!std.mem.eql(u8, m, milestone)) continue;
        const t = project.schema.itemType(w.item.type_name).?;
        const weight: f64 = switch (count) {
            .items => 1,
            .weight => @floatFromInt(w.estimate orelse w.duration orelse 1),
        };
        total += weight;
        const finished = t.planning.?.doneStatuses(t.statuses, t.tombstone);
        if (Schema.names.contains(finished, w.item.effectiveStatus(t))) done += weight;
    }
    return .{ .total = total, .done = done };
}

/// The points from `first` to `last` (and no later than `today`): each day
/// as committed by its end, today as the files are (`now`)
pub fn compute(io: Io, arena: std.mem.Allocator, root: Io.Dir, now: struct { project: *const Project, graph: *const Graph }, milestone: []const u8, first: day.Day, last: day.Day, today: day.Day, count: Count) ![]const Point {
    const commits = try commitsOf(io, arena, root);
    var measured: std.StringHashMapUnmanaged(struct { total: f64, done: f64 }) = .empty;
    var out: std.ArrayList(Point) = .empty;
    var d = first;
    while (d <= @min(last, today)) : (d += 1) {
        if (d == today) {
            const m = try measure(arena, now.project, now.graph, milestone, count);
            try out.append(arena, .{ .day = d, .total = m.total, .done = m.done });
            continue;
        }
        // the last commit made on or before the day
        const commit = for (commits) |c| {
            if (c.day <= d) break c.hash;
        } else {
            try out.append(arena, .{ .day = d, .total = 0, .done = 0 });
            continue;
        };
        const e = try measured.getOrPut(arena, commit);
        if (!e.found_existing) {
            var snap = history.snapshot(io, arena, root, commit) catch {
                e.value_ptr.* = .{ .total = 0, .done = 0 };
                try out.append(arena, .{ .day = d, .total = 0, .done = 0 });
                continue;
            };
            defer snap.deinit();
            const m = try measure(arena, &snap.project, &snap.graph, milestone, count);
            e.value_ptr.* = .{ .total = m.total, .done = m.done };
        }
        try out.append(arena, .{ .day = d, .total = e.value_ptr.total, .done = e.value_ptr.done });
    }
    return out.items;
}

const Commit = struct { hash: []const u8, day: day.Day };

/// The commits of the first-parent history of HEAD, newest first, with the
/// day each was committed
fn commitsOf(io: Io, arena: std.mem.Allocator, root: Io.Dir) ![]const Commit {
    const text = try git.output(io, arena, root, &.{ "log", "--first-parent", "--format=%H %cs", "HEAD" }) orelse return &.{};
    var out: std.ArrayList(Commit) = .empty;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const space = std.mem.findScalar(u8, line, ' ') orelse continue;
        const d = day.parse(std.mem.trim(u8, line[space + 1 ..], " \r")) orelse continue;
        try out.append(arena, .{ .hash = line[0..space], .day = d });
    }
    return out.items;
}
