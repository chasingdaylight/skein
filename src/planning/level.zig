//! Releveling (#94): a schedule in which nobody has more work in a week
//! than they can do, by moving work later. The work is taken in the order
//! of its start, critical work first among work that starts the same day;
//! each item starts no earlier than its predecessors' new finishes allow,
//! and then on the first working day from which its hours, counted as
//! `skein load` counts them, fit beside what is booked already for each of
//! its assignees, week by week. Finished work stays where it is and is
//! booked. Work that cannot fit within two years stays where it was and is
//! listed. Nothing is written here: `skein level` proposes the moves.

const std = @import("std");

const Calendar = @import("Calendar.zig");
const Resources = @import("Resources.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");
const schedule = @import("schedule.zig");

const Error = std.mem.Allocator.Error;

/// The longest skein looks for room, in working days
const limit = 520;

pub const Move = struct {
    entry: *const schedule.Entry,
    start: day.Day,
    finish: day.Day,
    /// for a float item with predecessors: the working days to wait after
    /// them, beyond its lag, that the move needs; 0 when they move it
    extra_lag: u32 = 0,
};

pub const Result = struct {
    /// the work whose dates change, in the order it was placed
    moves: []const Move,
    /// the work that found no room
    stuck: []const *const Work,
};

/// Hours booked per person, by the Monday of each week
const Booked = std.StringHashMapUnmanaged(std.AutoHashMapUnmanaged(day.Day, f64));

pub fn level(arena: std.mem.Allocator, works: []const Work, resources: *const Resources) Error!Result {
    const calendar = &resources.calendar;
    const entries = try schedule.compute(arena, works, calendar);
    var order: std.ArrayList(*const schedule.Entry) = .empty;
    for (entries) |*e| if (e.start != null and e.finish != null) try order.append(arena, e);
    std.mem.sort(*const schedule.Entry, order.items, {}, struct {
        fn lt(_: void, a: *const schedule.Entry, b: *const schedule.Entry) bool {
            if (a.start.? != b.start.?) return a.start.? < b.start.?;
            const sa = a.slack orelse std.math.maxInt(u32);
            const sb = b.slack orelse std.math.maxInt(u32);
            if (sa != sb) return sa < sb;
            // then in the order of the plan
            return @intFromPtr(a) < @intFromPtr(b);
        }
    }.lt);

    var booked: Booked = .empty;
    var finishes: std.StringHashMapUnmanaged(day.Day) = .empty;
    var moves: std.ArrayList(Move) = .empty;
    var stuck: std.ArrayList(*const Work) = .empty;
    for (order.items) |e| {
        const w = e.work;
        const length = @max(1, calendar.workingDays(e.start.?, e.finish.?));
        var start = e.start.?;
        // after the predecessors, as they finish now
        var from_predecessors: ?day.Day = null;
        if (!w.done and w.after.len > 0) for (w.after) |id| {
            const f = finishes.get(id) orelse continue;
            const s = calendar.forward(calendar.next(f), w.lag);
            if (from_predecessors == null or s > from_predecessors.?) from_predecessors = s;
        };
        if (from_predecessors) |s| if (s > start) {
            start = s;
        };
        const per_day = hoursPerDay(w, length, calendar);
        if (!w.done and per_day > 0) {
            var tries: u32 = 0;
            const first_try = calendar.atOrAfter(start);
            var s = first_try;
            while (tries < limit and !try fits(arena, &booked, resources, w, s, calendar.finishOf(s, length), per_day)) : (tries += 1) s = calendar.next(s);
            if (tries == limit) try stuck.append(arena, w) else start = s;
        }
        const finish = calendar.finishOf(start, length);
        try book(arena, &booked, resources, w, start, finish, per_day);
        try finishes.put(arena, w.id, finish);
        if (start != e.start.?) {
            var extra: u32 = 0;
            if (e.mode == .float and w.after.len > 0) if (from_predecessors) |base| if (start > base) {
                extra = calendar.workingDays(base, start) - 1;
            };
            try moves.append(arena, .{ .entry = e, .start = start, .finish = finish, .extra_lag = extra });
        }
    }
    return .{ .moves = moves.items, .stuck = stuck.items };
}

/// The hours a day of the work takes of each of its assignees, as
/// `skein load` spreads them; 0 for work with none
fn hoursPerDay(w: *const Work, length: u32, calendar: *const Calendar) f64 {
    if (w.assignees.len == 0) return 0;
    const effort: f64 = @floatFromInt(w.estimate orelse w.duration orelse length);
    return effort * calendar.hours / @as(f64, @floatFromInt(length)) / @as(f64, @floatFromInt(w.assignees.len));
}

/// Whether the work, from `first` to `last`, fits beside what each of its
/// assignees has booked, week by week; one who is not among the people
/// has no limit
fn fits(arena: std.mem.Allocator, booked: *Booked, resources: *const Resources, w: *const Work, first: day.Day, last: day.Day, per_day: f64) Error!bool {
    var weeks: std.AutoArrayHashMapUnmanaged(day.Day, f64) = .empty;
    var d = first;
    while (d <= last) : (d += 1) {
        if (!resources.calendar.isWorking(d)) continue;
        const e = try weeks.getOrPut(arena, day.monday(d));
        if (!e.found_existing) e.value_ptr.* = 0;
        e.value_ptr.* += per_day;
    }
    for (w.assignees) |handle| {
        const p = resources.person(handle) orelse continue;
        const mine = booked.get(handle);
        for (weeks.keys(), weeks.values()) |monday, hours| {
            var capacity: f64 = 0;
            for (0..7) |i| capacity += p.capacity(monday + @as(day.Day, @intCast(i)));
            const already = if (mine) |m| m.get(monday) orelse 0 else 0;
            if (already + hours > capacity + 0.01) return false;
        }
    }
    return true;
}

fn book(arena: std.mem.Allocator, booked: *Booked, resources: *const Resources, w: *const Work, first: day.Day, last: day.Day, per_day: f64) Error!void {
    if (per_day == 0) return;
    for (w.assignees) |handle| {
        const e = try booked.getOrPut(arena, handle);
        if (!e.found_existing) e.value_ptr.* = .empty;
        var d = first;
        while (d <= last) : (d += 1) {
            if (!resources.calendar.isWorking(d)) continue;
            const week = try e.value_ptr.getOrPut(arena, day.monday(d));
            if (!week.found_existing) week.value_ptr.* = 0;
            week.value_ptr.* += per_day;
        }
    }
}
