//! The Gantt chart a document asks for, as a Mermaid `gantt` diagram, with
//! a table of the dates, slack and predecessors under it:
//!
//!     ```skein
//!     gantt [TYPE...] [category=C] [status=S] [profile=P] [ATTRIBUTE=V]
//!           [by=parent|assignee] [baseline=NAME]
//!     ```
//!
//! Bars on the critical path are marked critical, work of no duration is a
//! milestone, and with `baseline=NAME` each item's bar in the schedule
//! stored at that baseline (a tag) is drawn under its bar now.

const std = @import("std");

const Calendar = @import("../planning/Calendar.zig");
const burn_points = @import("../planning/burn.zig");
const day = @import("../planning/day.zig");
const generated = @import("generated.zig");
const Work = @import("../planning/Work.zig");
const schedule = @import("../planning/schedule.zig");
const toml = @import("../toml.zig");

pub const Error = generated.Error;

/// The schedule, for the pages that draw it
pub const Plan = struct {
    /// the work items, with what the forge holds of their issues
    works: []const Work,
    entries: []const schedule.Entry,
    calendar: *const Calendar,
    /// The bars of the schedule stored at a baseline; null when the baseline
    /// or its schedule is not there
    baseline: *const fn (ctx: *const anyopaque, name: []const u8) Error!?[]const Bar,
    /// The days of a milestone's burndown and burnup, read from git
    burn: *const fn (ctx: *const anyopaque, milestone: []const u8, first: day.Day, last: day.Day, count: burn_points.Count) Error![]const burn_points.Point,
    /// what `baseline` and `burn` draw on
    baseline_ctx: *const anyopaque,
    /// the day it is, for what is drawn up to today
    today: day.Day,
};

pub const Bar = struct { id: []const u8, start: day.Day, finish: day.Day };

/// The bars of a stored schedule's text; null when it is no schedule
pub fn barsOf(arena: std.mem.Allocator, text: []const u8) Error!?[]const Bar {
    var diag: toml.Diagnostic = .{};
    const root = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const items = root.get("items") orelse return null;
    if (items != .table) return null;
    var out: std.ArrayList(Bar) = .empty;
    for (items.table.keys()) |id| {
        const t = items.table.get(id).?;
        if (t != .table) continue;
        const start = dateOf(t.table.get("start")) orelse continue;
        const finish = dateOf(t.table.get("finish")) orelse continue;
        try out.append(arena, .{ .id = id, .start = start, .finish = finish });
    }
    return out.items;
}

fn dateOf(v: ?toml.Value) ?day.Day {
    const value = v orelse return null;
    if (value != .datetime) return null;
    const d = value.datetime.date orelse return null;
    return day.fromCivil(d.year, d.month, d.day);
}

pub fn render(ctx: generated.Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const plan = ctx.planning orelse return a.print("> **skein:** the schedule is not drawn here\n", .{});
    var by: enum { parent, assignee } = .parent;
    var baseline: ?[]const u8 = null;
    var conditions: std.ArrayList([]const u8) = .empty;
    for (args) |word| {
        if (std.mem.startsWith(u8, word, "by=")) {
            const v = word["by=".len..];
            by = if (std.mem.eql(u8, v, "parent")) .parent else if (std.mem.eql(u8, v, "assignee")) .assignee else return a.print("> **skein:** by= takes parent or assignee, not '{s}'\n", .{v});
        } else if (std.mem.startsWith(u8, word, "baseline=")) {
            baseline = word["baseline=".len..];
        } else try conditions.append(a, word);
    }
    var filter: generated.Filter = .{ .profile = ctx.default_profile };
    if (try generated.readFilter(ctx, conditions.items, &filter, true)) |message| return message;

    var shown: std.ArrayList(*const schedule.Entry) = .empty;
    var unscheduled: std.ArrayList(*const schedule.Entry) = .empty;
    for (plan.entries) |*e| {
        if (!filter.passes(&ctx.project.schema, ctx.graph, e.work.item)) continue;
        if (e.start == null or e.finish == null) try unscheduled.append(a, e) else try shown.append(a, e);
    }
    if (shown.items.len == 0 and unscheduled.items.len == 0) return a.print("*No work item is selected.*\n", .{});
    const old: ?[]const Bar = if (baseline) |name| try plan.baseline(plan.baseline_ctx, name) orelse
        return a.print("> **skein:** there is no schedule stored at the baseline '{s}'\n", .{name}) else null;

    var out: std.ArrayList(u8) = .empty;
    if (shown.items.len > 0) {
        try out.appendSlice(a, "```mermaid\ngantt\n  dateFormat YYYY-MM-DD\n");
        try excludes(a, &out, plan.calendar);
        var rows: Rows = .{ .a = a, .out = &out, .old = old, .baseline = baseline orelse "" };
        switch (by) {
            .parent => try byParent(&rows, shown.items),
            .assignee => try byAssignee(&rows, shown.items),
        }
        try out.appendSlice(a, "```\n\n");
        try table(ctx, &out, shown.items);
    }
    if (unscheduled.items.len > 0) {
        try out.appendSlice(a, if (shown.items.len > 0) "\nNot scheduled: " else "Not scheduled: ");
        for (unscheduled.items, 0..) |e, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            try generated.link(ctx, &out, e.work.item);
        }
        try out.appendSlice(a, ".\n");
    }
    return out.items;
}

/// The days the chart leaves out: those that are not working days
fn excludes(a: std.mem.Allocator, out: *std.ArrayList(u8), calendar: *const Calendar) Error!void {
    const names = [_][]const u8{ "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" };
    if (!calendar.works()) return;
    var list: std.ArrayList([]const u8) = .empty;
    if (!calendar.workdays[5] and !calendar.workdays[6]) try list.append(a, "weekends");
    for (calendar.workdays, 0..) |w, i| {
        if (w or (i >= 5 and !calendar.workdays[5] and !calendar.workdays[6])) continue;
        try list.append(a, names[i]);
    }
    for (calendar.holidays) |h| try list.append(a, try a.dupe(u8, &day.format(h)));
    if (list.items.len > 0) try out.print(a, "  excludes {s}\n", .{try std.mem.join(a, ", ", list.items)});
}

/// The rows of the chart, each item's bar and, at a baseline, its bar then
const Rows = struct {
    a: std.mem.Allocator,
    out: *std.ArrayList(u8),
    old: ?[]const Bar,
    baseline: []const u8,
    n: usize = 0,

    fn section(self: *Rows, name: []const u8) Error!void {
        try self.out.print(self.a, "  section {s}\n", .{name});
    }

    fn bar(self: *Rows, e: *const schedule.Entry) Error!void {
        const a = self.a;
        const id = e.work.item.id;
        self.n += 1;
        const start = e.start.?;
        const finish = e.finish.?;
        if (e.work.duration != null and e.work.duration.? == 0) {
            try self.out.print(a, "  {s} :milestone, t{d}, {s}, 0d\n", .{ id, self.n, &day.format(start) });
        } else {
            // the end Mermaid takes is the day after the last
            try self.out.print(a, "  {s} :{s}t{d}, {s}, {s}\n", .{ id, if (e.critical()) "crit, " else "", self.n, &day.format(start), &day.format(finish + 1) });
        }
        const old = self.old orelse return;
        for (old) |b| if (std.mem.eql(u8, b.id, id)) {
            self.n += 1;
            try self.out.print(a, "  {s} at {s} :done, t{d}, {s}, {s}\n", .{ id, self.baseline, self.n, &day.format(b.start), &day.format(b.finish + 1) });
            break;
        };
    }
};

/// A section for each item with parts, holding it and its parts; the rest
/// together
fn byParent(rows: *Rows, entries: []const *const schedule.Entry) Error!void {
    var done: std.StringHashMapUnmanaged(void) = .empty;
    for (entries) |e| {
        const id = e.work.item.id;
        var parts: std.ArrayList(*const schedule.Entry) = .empty;
        for (entries) |c| for (c.work.parents) |p| if (std.mem.eql(u8, p, id)) {
            try parts.append(rows.a, c);
            break;
        };
        if (parts.items.len == 0) continue;
        try rows.section(id);
        try rows.bar(e);
        try done.put(rows.a, id, {});
        for (parts.items) |c| {
            if ((try done.getOrPut(rows.a, c.work.item.id)).found_existing) continue;
            try rows.bar(c);
        }
    }
    var rest = false;
    for (entries) |e| {
        if (done.contains(e.work.item.id)) continue;
        if (!rest) try rows.section("Work");
        rest = true;
        try rows.bar(e);
    }
}

/// A section for each assignee; work of several in each of theirs
fn byAssignee(rows: *Rows, entries: []const *const schedule.Entry) Error!void {
    var people: std.ArrayList([]const u8) = .empty;
    for (entries) |e| for (e.work.assignees) |p| {
        for (people.items) |q| {
            if (std.mem.eql(u8, p, q)) break;
        } else try people.append(rows.a, p);
    };
    for (people.items) |p| {
        try rows.section(p);
        for (entries) |e| for (e.work.assignees) |q| if (std.mem.eql(u8, p, q)) {
            try rows.bar(e);
            break;
        };
    }
    var rest = false;
    for (entries) |e| {
        if (e.work.assignees.len > 0) continue;
        if (!rest) try rows.section("Unassigned");
        rest = true;
        try rows.bar(e);
    }
}

fn table(ctx: generated.Context, out: *std.ArrayList(u8), entries: []const *const schedule.Entry) Error!void {
    const a = ctx.arena;
    try out.appendSlice(a, "| Item | Start | Finish | Slack | After |\n| --- | --- | --- | ---: | --- |\n");
    for (entries) |e| {
        try out.appendSlice(a, "| ");
        try generated.link(ctx, out, e.work.item);
        try out.print(a, " | {s} | {s} | ", .{ &day.format(e.start.?), &day.format(e.finish.?) });
        if (e.slack) |s| try out.print(a, "{s}{d}", .{ if (e.critical()) "**critical** " else "", s });
        try out.appendSlice(a, " | ");
        for (e.work.after, 0..) |id, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            if (ctx.graph.find(id)) |item| try generated.link(ctx, out, item) else try out.print(a, "`{s}`", .{id});
        }
        try out.appendSlice(a, " |\n");
    }
}
