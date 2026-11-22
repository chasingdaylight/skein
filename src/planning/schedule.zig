//! The schedule of the work items: fixed items keep the dates written for
//! them; a float item starts on the first working day after all its
//! predecessors have finished (plus its lag), or, with none, when its
//! parent starts; a parent that has neither spans its children. Then the
//! slack of each, backward from the end of the plan, and the critical
//! path: the items without slack.

const std = @import("std");

const Calendar = @import("Calendar.zig");
const Planning = @import("../schema/Planning.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");

const Error = std.mem.Allocator.Error;

pub const Source = enum {
    /// the dates written for a fixed item
    written,
    /// computed from predecessors, parents or children
    computed,
    /// a float item with nothing to schedule it from
    unscheduled,
    /// its finish is the due day of its issue's milestone on the forge, its
    /// start that many working days before
    forge,
};

pub const Entry = struct {
    work: *const Work,
    mode: Planning.Mode,
    source: Source,
    start: ?day.Day = null,
    finish: ?day.Day = null,
    /// working days it can slip without moving the end of the plan
    slack: ?u32 = null,

    pub fn critical(self: *const Entry) bool {
        return self.slack != null and self.slack.? == 0;
    }
};

pub fn compute(arena: std.mem.Allocator, works: []const Work, calendar: *const Calendar) Error![]Entry {
    const entries = try arena.alloc(Entry, works.len);
    for (works, entries) |*w, *e| {
        const mode = w.mode() orelse .float;
        e.* = .{ .work = w, .mode = mode, .source = if (mode == .fixed) .written else .unscheduled };
        if (mode == .fixed) {
            e.start = w.start;
            if (w.start) |s| e.finish = w.lastDay(calendar) orelse s;
        } else if (w.forge_due) |due| if (w.after.len == 0 and w.start == null) {
            // what the forge says is due, when nothing else places it
            e.finish = due;
            e.start = calendar.back(due, (w.duration orelse 1) -| 1);
            e.source = .forge;
        };
    }
    // each pass schedules what it can; a loop of predecessors stays unscheduled
    var changed = true;
    while (changed) {
        changed = false;
        for (entries) |*e| {
            if (e.mode == .fixed or e.source != .unscheduled) continue;
            const start = startOf(entries, e, calendar) orelse continue;
            e.start = start;
            e.finish = calendar.finishOf(start, e.work.duration orelse 1);
            e.source = .computed;
            changed = true;
        }
        for (entries) |*e| {
            if (e.mode == .fixed or e.source != .unscheduled or e.work.after.len > 0) continue;
            if (span(entries, e)) |s| {
                e.start = s.first;
                e.finish = s.last;
                e.source = .computed;
                changed = true;
            }
        }
    }
    try slacks(arena, entries, calendar);
    return entries;
}

fn find(entries: []Entry, id: []const u8) ?*Entry {
    for (entries) |*e| if (std.mem.eql(u8, e.work.id, id)) return e;
    return null;
}

/// When a float item can start: after its predecessors, else with its
/// parent; null while what it waits for has no dates
fn startOf(entries: []Entry, e: *const Entry, calendar: *const Calendar) ?day.Day {
    if (e.work.after.len > 0) {
        var latest: ?day.Day = null;
        for (e.work.after) |id| {
            const before = find(entries, id) orelse continue;
            const finish = before.finish orelse return null;
            if (latest == null or finish > latest.?) latest = finish;
        }
        return calendar.forward(calendar.next(latest orelse return null), e.work.lag);
    }
    for (e.work.parents) |id| {
        const parent = find(entries, id) orelse continue;
        // a parent that spans its children gives them no start
        if (parent.source == .written or (parent.source == .computed and parent.work.after.len > 0)) {
            return calendar.atOrAfter(parent.start orelse continue);
        }
    }
    return null;
}

/// The days the children of `e` span, once all have dates; null when it
/// has no children, or some have none yet
fn span(entries: []Entry, e: *const Entry) ?Calendar.Range {
    var out: ?Calendar.Range = null;
    for (entries) |*child| {
        const is_child = for (child.work.parents) |p| {
            if (std.mem.eql(u8, p, e.work.id)) break true;
        } else false;
        if (!is_child) continue;
        const first = child.start orelse return null;
        const last = child.finish orelse return null;
        if (out) |*r| {
            r.first = @min(r.first, first);
            r.last = @max(r.last, last);
        } else out = .{ .first = first, .last = last };
    }
    return out;
}

/// The slack of every item with dates: how many working days it can
/// finish later before an item after it, or the end of the plan, moves
fn slacks(arena: std.mem.Allocator, entries: []Entry, calendar: *const Calendar) Error!void {
    var end: ?day.Day = null;
    for (entries) |e| if (e.finish) |f| {
        if (end == null or f > end.?) end = f;
    };
    const plan_end = end orelse return;
    // the latest finish of each, null until known, from the items after it
    const latest = try arena.alloc(?day.Day, entries.len);
    @memset(latest, null);
    const visiting = try arena.alloc(bool, entries.len);
    @memset(visiting, false);
    for (entries, 0..) |*e, i| {
        const finish = e.finish orelse continue;
        const lf = latestFinish(entries, latest, visiting, i, plan_end, calendar);
        e.slack = if (lf > finish) calendar.workingDays(calendar.next(finish), lf) else 0;
    }
}

fn latestFinish(entries: []Entry, latest: []?day.Day, visiting: []bool, i: usize, plan_end: day.Day, calendar: *const Calendar) day.Day {
    if (latest[i]) |l| return l;
    // in a loop of predecessors, the end of the plan
    if (visiting[i]) return plan_end;
    visiting[i] = true;
    defer visiting[i] = false;
    var out = plan_end;
    const id = entries[i].work.id;
    for (entries, 0..) |*after, j| {
        const follows = for (after.work.after) |p| {
            if (std.mem.eql(u8, p, id)) break true;
        } else false;
        if (!follows) continue;
        const start = after.start orelse continue;
        const finish = after.finish orelse continue;
        const length = calendar.workingDays(start, finish);
        const latest_start = calendar.back(latestFinish(entries, latest, visiting, j, plan_end, calendar), if (length > 0) length - 1 else 0);
        const must_finish = calendar.back(calendar.previous(latest_start), after.work.lag);
        out = @min(out, must_finish);
    }
    latest[i] = out;
    return out;
}
