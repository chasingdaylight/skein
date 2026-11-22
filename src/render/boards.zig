//! Boards and the roadmap a document asks for, as Markdown tables:
//!
//!     ```skein
//!     board [TYPE...] [conditions] [by=status|assignee|milestone]
//!     roadmap [MILESTONE...]
//!     ```
//!
//! A board has a column for each status (in the order of the types'
//! statuses), assignee or milestone, and a card for each work item in its
//! column: its ID, linked, and the first line of its text. The roadmap has
//! a row for each milestone, the work items that work names as its
//! milestone, in the order of their finish: its dates, how much of its work
//! is done, and the work in it.

const std = @import("std");

const Schema = @import("../schema/Schema.zig");
const burn = @import("../planning/burn.zig");
const day = @import("../planning/day.zig");
const generated = @import("generated.zig");
const Time = @import("../planning/Time.zig");
const schedule = @import("../planning/schedule.zig");

const Error = generated.Error;

const Column = struct { name: []const u8, entries: std.ArrayList(*const schedule.Entry) = .empty };

pub fn board(ctx: generated.Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const plan = ctx.planning orelse return a.print("> **skein:** there are no work items to put on a board\n", .{});
    var by: enum { status, assignee, milestone } = .status;
    var conditions: std.ArrayList([]const u8) = .empty;
    for (args) |word| {
        if (std.mem.startsWith(u8, word, "by=")) {
            const v = word["by=".len..];
            by = std.meta.stringToEnum(@TypeOf(by), v) orelse return a.print("> **skein:** by= takes status, assignee or milestone, not '{s}'\n", .{v});
        } else try conditions.append(a, word);
    }
    var filter: generated.Filter = .{ .profile = ctx.default_profile };
    if (try generated.readFilter(ctx, conditions.items, &filter, true)) |message| return message;
    const schema = &ctx.project.schema;

    var columns: std.ArrayList(Column) = .empty;
    if (by == .status) {
        // the statuses of the work types, in their order, as the board's columns
        for (schema.types) |t| {
            if (t.planning == null) continue;
            if (filter.types.items.len > 0 and !Schema.names.contains(filter.types.items, t.name)) continue;
            for (t.statuses) |s| {
                if (t.tombstone != null and std.mem.eql(u8, s, t.tombstone.?)) continue;
                _ = try columnOf(a, &columns, s);
            }
        }
    }
    var shown: usize = 0;
    for (plan.entries) |*e| {
        if (!generated.passesWork(&filter, schema, ctx.graph, e.work)) continue;
        shown += 1;
        switch (by) {
            .status => try (try columnOf(a, &columns, generated.statusOf(schema, e.work))).entries.append(a, e),
            .milestone => try (try columnOf(a, &columns, e.work.milestone orelse "(none)")).entries.append(a, e),
            .assignee => {
                if (e.work.assignees.len == 0) try (try columnOf(a, &columns, "(unassigned)")).entries.append(a, e);
                for (e.work.assignees) |p| try (try columnOf(a, &columns, p)).entries.append(a, e);
            },
        }
    }
    if (shown == 0) return a.print("*No work item is selected.*\n", .{});

    var out: std.ArrayList(u8) = .empty;
    var rows: usize = 0;
    try out.appendSlice(a, "|");
    for (columns.items) |c| {
        try out.print(a, " {s} ({d}) |", .{ c.name, c.entries.items.len });
        rows = @max(rows, c.entries.items.len);
    }
    try out.appendSlice(a, "\n|");
    for (columns.items) |_| try out.appendSlice(a, " --- |");
    try out.append(a, '\n');
    for (0..rows) |r| {
        try out.append(a, '|');
        for (columns.items) |c| {
            try out.append(a, ' ');
            if (r < c.entries.items.len) try card(ctx, &out, c.entries.items[r]);
            try out.appendSlice(a, " |");
        }
        try out.append(a, '\n');
    }
    return out.items;
}

fn columnOf(a: std.mem.Allocator, columns: *std.ArrayList(Column), name: []const u8) Error!*Column {
    for (columns.items) |*c| if (std.mem.eql(u8, c.name, name)) return c;
    try columns.append(a, .{ .name = name });
    return &columns.items[columns.items.len - 1];
}

/// A card: the ID, linked, and the first line of the text
fn card(ctx: generated.Context, out: *std.ArrayList(u8), e: *const schedule.Entry) Error!void {
    try generated.linkWork(ctx, out, e.work);
    const first = generated.firstParagraph(e.work.item.text);
    const line = first[0 .. std.mem.findScalar(u8, first, '\n') orelse first.len];
    if (line.len > 0) {
        try out.appendSlice(ctx.arena, " ");
        try generated.cell(ctx.arena, out, line);
    }
}

/// `time [TYPE...] [conditions]`: the estimate of each work item that has
/// one or time spent, what was spent and by whom, and the difference
pub fn timeTable(ctx: generated.Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const plan = ctx.planning orelse return a.print("> **skein:** there are no work items to show time for\n", .{});
    var filter: generated.Filter = .{ .profile = ctx.default_profile };
    if (try generated.readFilter(ctx, args, &filter, true)) |message| return message;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "| Item | Estimate (h) | Spent (h) | Difference (h) | By |\n| --- | ---: | ---: | ---: | --- |\n");
    var estimate: f64 = 0;
    var spent: f64 = 0;
    var rows: usize = 0;
    for (try Time.summarize(a, plan.works, plan.spent, plan.hours_a_day)) |r| {
        if (!generated.passesWork(&filter, &ctx.project.schema, ctx.graph, r.work)) continue;
        rows += 1;
        try out.appendSlice(a, "| ");
        try generated.linkWork(ctx, &out, r.work);
        if (r.estimate) |e| {
            try out.print(a, " | {d:.1} | {d:.1} | {s}{d:.1} |", .{ e, r.spent, if (r.spent > e) "+" else "", r.spent - e });
            estimate += e;
        } else try out.print(a, " | | {d:.1} | |", .{r.spent});
        spent += r.spent;
        try out.append(a, ' ');
        for (r.by, 0..) |b, i| try out.print(a, "{s}{s} {d:.1}", .{ if (i > 0) ", " else "", b.name, b.hours });
        try out.appendSlice(a, " |\n");
    }
    if (rows == 0) return a.print("*No work item has an estimate or time spent.*\n", .{});
    try out.print(a, "| **In all** | {d:.1} | {d:.1} | {s}{d:.1} | |\n", .{ estimate, spent, if (spent > estimate) "+" else "", spent - estimate });
    return out.items;
}

pub fn roadmap(ctx: generated.Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const plan = ctx.planning orelse return a.print("> **skein:** there are no work items for a roadmap\n", .{});
    // the milestones: those named, else every one that work names
    var names: std.ArrayList([]const u8) = .empty;
    try names.appendSlice(a, args);
    if (args.len == 0) for (plan.entries) |e| {
        const m = e.work.milestone orelse continue;
        if (!Schema.names.contains(names.items, m)) try names.append(a, m);
    };
    if (names.items.len == 0) return a.print("*No work names a milestone.*\n", .{});
    const Row = struct { name: []const u8, entry: ?*const schedule.Entry };
    var rows: std.ArrayList(Row) = .empty;
    for (names.items) |n| {
        const entry = for (plan.entries) |*e| {
            if (std.mem.eql(u8, e.work.id, n)) break e;
        } else null;
        try rows.append(a, .{ .name = n, .entry = entry });
    }
    // by finish, those without one last
    std.mem.sort(Row, rows.items, {}, struct {
        fn lt(_: void, x: Row, y: Row) bool {
            const fx = if (x.entry) |e| e.finish else null;
            const fy = if (y.entry) |e| e.finish else null;
            if (fx == null) return false;
            if (fy == null) return true;
            return fx.? < fy.?;
        }
    }.lt);

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "| Milestone | Start | Finish | Done | Work |\n| --- | --- | --- | --- | --- |\n");
    for (rows.items) |r| {
        try out.appendSlice(a, "| ");
        if (ctx.graph.find(r.name)) |item| try generated.link(ctx, &out, item) else try out.print(a, "`{s}`", .{r.name});
        // its dates: its own, else those its work spans
        var first: ?day.Day = if (r.entry) |e| e.start else null;
        const last: ?day.Day = if (r.entry) |e| e.finish else null;
        var work: std.ArrayList(*const schedule.Entry) = .empty;
        for (plan.entries) |*e| {
            const m = e.work.milestone orelse continue;
            if (!std.mem.eql(u8, m, r.name)) continue;
            try work.append(a, e);
            if (e.start) |s| if (first == null or s < first.?) {
                first = s;
            };
        }
        try out.print(a, " | {s} | {s} | ", .{ if (first) |d| try a.dupe(u8, &day.format(d)) else "", if (last) |d| try a.dupe(u8, &day.format(d)) else "" });
        const m = burn.measure(plan.works, r.name, .items);
        const percent: u64 = if (m.total == 0) 0 else @intFromFloat(@round(m.done * 100 / m.total));
        try out.print(a, "{d} of {d} ({d}%) {s} | ", .{ @as(u64, @intFromFloat(m.done)), @as(u64, @intFromFloat(m.total)), percent, try bar(a, percent) });
        for (work.items, 0..) |e, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            try generated.linkWork(ctx, &out, e.work);
        }
        try out.appendSlice(a, " |\n");
    }
    return out.items;
}

/// How far along, in ten blocks
fn bar(a: std.mem.Allocator, percent: u64) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const full = @min(10, (percent + 5) / 10);
    for (0..10) |i| try out.appendSlice(a, if (i < full) "\u{2588}" else "\u{2591}");
    return out.items;
}
