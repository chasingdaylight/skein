//! Each person's load, week by week: the effort of the work assigned to
//! them (its estimate, else its duration, in days of the calendar's hours),
//! spread evenly over its working days and shared among its assignees,
//! beside what the person can work that week. Work without dates is not
//! counted until it is scheduled.

const std = @import("std");

const Calendar = @import("Calendar.zig");
const Graph = @import("../graph/Graph.zig");
const Report = @import("../Report.zig");
const Resources = @import("Resources.zig");
const Schema = @import("../schema/Schema.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");

const Error = std.mem.Allocator.Error;

pub const Week = struct {
    monday: day.Day,
    hours: f64 = 0,
    capacity: f64 = 0,

    pub fn over(self: Week) bool {
        return self.hours > self.capacity + 0.01;
    }
};

pub const Load = struct {
    person: *const Resources.Person,
    /// in order, each week with work
    weeks: []const Week,
};

pub fn compute(arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, resources: *const Resources) Error![]const Load {
    const works = try Work.collect(arena, schema, graph);
    var out: std.ArrayList(Load) = .empty;
    for (resources.people) |*p| {
        var weeks: std.array_hash_map.Auto(day.Day, Week) = .empty;
        for (works) |*w| {
            if (!assigned(w, p.handle)) continue;
            const first = w.start orelse continue;
            const last = w.lastDay(&resources.calendar) orelse continue;
            const working = resources.calendar.workingDays(first, last);
            if (working == 0) continue;
            const effort: f64 = @floatFromInt(w.estimate orelse w.duration orelse working);
            const per_day = effort * resources.calendar.hours / @as(f64, @floatFromInt(working)) / @as(f64, @floatFromInt(w.assignees.len));
            var d = first;
            while (d <= last) : (d += 1) {
                if (!resources.calendar.isWorking(d)) continue;
                const e = try weeks.getOrPut(arena, day.monday(d));
                if (!e.found_existing) e.value_ptr.* = .{ .monday = day.monday(d) };
                e.value_ptr.hours += per_day;
            }
        }
        const sorted = weeks.values();
        std.mem.sort(Week, sorted, {}, struct {
            fn lt(_: void, a: Week, b: Week) bool {
                return a.monday < b.monday;
            }
        }.lt);
        for (sorted) |*week| {
            for (0..7) |i| week.capacity += p.capacity(week.monday + @as(day.Day, @intCast(i)));
        }
        try out.append(arena, .{ .person = p, .weeks = sorted });
    }
    return out.items;
}

fn assigned(w: *const Work, handle: []const u8) bool {
    for (w.assignees) |a| if (std.mem.eql(u8, a, handle)) return true;
    return false;
}

/// Reports assignees who are not among the people, and warns of each
/// week a person has more work than time
pub fn check(arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, resources: *const Resources, report: *Report) Error!void {
    for (try Work.collect(arena, schema, graph)) |*w| {
        for (w.assignees) |a| if (resources.person(a) == null) {
            try report.add(w.item.file, w.item.line, 1, "{s}: '{s}' is not among the people of {s}", .{ w.item.id, a, Resources.file });
        };
    }
    for (try compute(arena, schema, graph, resources)) |l| {
        for (l.weeks) |week| if (week.over()) {
            try report.warn(Resources.file, l.person.line, 1, "{s} has {d:.1} hours of work in the week of {s} ({s}), and {d:.1} hours to work", .{ l.person.handle, week.hours, &day.format(week.monday), &day.isoWeek(week.monday), week.capacity });
        };
    }
}
