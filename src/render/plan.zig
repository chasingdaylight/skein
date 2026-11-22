//! The schedule for rendering: computed from the items with the project's
//! calendar, as `skein schedule` stores it, and the schedules stored at
//! baselines, read from git.

const std = @import("std");
const Io = std.Io;

const Calendar = @import("../planning/Calendar.zig");
const Resources = @import("../planning/Resources.zig");
const Report = @import("../Report.zig");
const Work = @import("../planning/Work.zig");
const Workspace = @import("../commands/Workspace.zig");
const gantt = @import("gantt.zig");
const git = @import("../git.zig");
const schedule = @import("../planning/schedule.zig");
const stored = @import("../planning/stored.zig");

/// The plan of the project; null when it has no work items. All of it is
/// in `arena`.
pub fn load(io: Io, arena: std.mem.Allocator, ws: *const Workspace) !?*const gantt.Plan {
    const works = try Work.collect(arena, &ws.project.schema, &ws.graph);
    if (works.len == 0) return null;
    // the resources file's mistakes are `check`'s to report
    var ignored: Report = .{ .arena = arena };
    const calendar = try arena.create(Calendar);
    calendar.* = if (try Resources.load(io, arena, ws.root, &ignored)) |r| r.calendar else .every_day;
    const at = try arena.create(Baselines);
    at.* = .{ .io = io, .arena = arena, .root = ws.root };
    const plan = try arena.create(gantt.Plan);
    plan.* = .{
        .entries = try schedule.compute(arena, works, calendar),
        .calendar = calendar,
        .baseline = Baselines.bars,
        .baseline_ctx = at,
    };
    return plan;
}

const Baselines = struct {
    io: Io,
    arena: std.mem.Allocator,
    root: Io.Dir,

    fn bars(ctx: *const anyopaque, name: []const u8) gantt.Error!?[]const gantt.Bar {
        const self: *const Baselines = @ptrCast(@alignCast(ctx));
        // a name git could take for an option is no tag
        if (name.len == 0 or name[0] == '-') return null;
        const text = try git.output(self.io, self.arena, self.root, &.{ "show", try self.arena.print("refs/tags/{s}:{s}", .{ name, stored.toml_file }) }) orelse return null;
        return gantt.barsOf(self.arena, text);
    }
};
