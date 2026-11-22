//! The schedule for rendering: computed from the items with the project's
//! calendar, as `skein schedule` stores it; the schedules stored at
//! baselines; and a milestone's history for burndown and burnup charts,
//! read from git.

const std = @import("std");
const Io = std.Io;

const Calendar = @import("../planning/Calendar.zig");
const Resources = @import("../planning/Resources.zig");
const Report = @import("../Report.zig");
const Time = @import("../planning/Time.zig");
const Work = @import("../planning/Work.zig");
const Workspace = @import("../commands/Workspace.zig");
const burn = @import("../planning/burn.zig");
const day = @import("../planning/day.zig");
const gantt = @import("gantt.zig");
const planning_forge = @import("../planning/forge.zig");
const git = @import("../git.zig");
const schedule = @import("../planning/schedule.zig");
const stored = @import("../planning/stored.zig");

/// The plan of the project; null when it has no work items. All of it is
/// in `arena`.
pub fn load(io: Io, arena: std.mem.Allocator, ws: *const Workspace, offline: bool) !?*const gantt.Plan {
    const works = (try planning_forge.collect(io, arena, ws.root, &ws.project, &ws.graph, offline)).works;
    if (works.len == 0) return null;
    // the resources file's mistakes are `check`'s to report
    var ignored: Report = .{ .arena = arena };
    const calendar = try arena.create(Calendar);
    calendar.* = if (try Resources.load(io, arena, ws.root, &ignored)) |r| r.calendar else .every_day;
    const spent = try Time.load(io, arena, ws.root, &ignored);
    const at = try arena.create(History);
    at.* = .{ .io = io, .arena = arena, .root = ws.root, .works = works };
    const plan = try arena.create(gantt.Plan);
    plan.* = .{
        .works = works,
        .spent = spent.all.items,
        .hours_a_day = calendar.hours,
        .entries = try schedule.compute(arena, works, calendar),
        .calendar = calendar,
        .baseline = History.bars,
        .burn = History.points,
        .baseline_ctx = at,
        .today = @intCast(@divFloor(Io.Clock.real.now(io).toSeconds(), 86400)),
    };
    return plan;
}

/// What the plan reads from git, and the project as it is
const History = struct {
    io: Io,
    arena: std.mem.Allocator,
    root: Io.Dir,
    works: []const Work,

    fn bars(ctx: *const anyopaque, name: []const u8) gantt.Error!?[]const gantt.Bar {
        const self: *const History = @ptrCast(@alignCast(ctx));
        // a name git could take for an option is no tag
        if (name.len == 0 or name[0] == '-') return null;
        const text = try git.output(self.io, self.arena, self.root, &.{ "show", try self.arena.print("refs/tags/{s}:{s}", .{ name, stored.toml_file }) }) orelse return null;
        return gantt.barsOf(self.arena, text);
    }

    fn points(ctx: *const anyopaque, milestone: []const u8, first: day.Day, last: day.Day, count: burn.Count) gantt.Error![]const burn.Point {
        const self: *const History = @ptrCast(@alignCast(ctx));
        const today: day.Day = @intCast(@divFloor(Io.Clock.real.now(self.io).toSeconds(), 86400));
        return burn.compute(self.io, self.arena, self.root, .{ .works = self.works }, milestone, first, last, today, count);
    }
};
