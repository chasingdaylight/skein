//! What `skein check` holds the schedule to: a fixed item that starts
//! before its predecessors let it, a child outside its parent's dates, an
//! item that finishes after its milestone, a float item with nothing to
//! schedule it from, and a stored schedule that is not the one the items
//! give now.

const std = @import("std");
const Io = std.Io;

const Calendar = @import("Calendar.zig");
const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");
const schedule = @import("schedule.zig");
const stored = @import("stored.zig");

const Error = std.mem.Allocator.Error;

pub fn run(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, calendar: *const Calendar, report: *Report) Error!void {
    const works = try Work.collect(arena, &project.schema, graph);
    if (works.len == 0) return;
    const entries = try schedule.compute(arena, works, calendar);
    for (entries) |*e| {
        const item = e.work.item;
        if (e.source == .unscheduled) {
            try report.warn(item.file, item.line, 1, "{s}: it cannot be scheduled: it follows nothing with dates, and has no parent with a start", .{item.id});
            continue;
        }
        const start = e.start orelse continue;
        const finish = e.finish orelse continue;
        if (e.mode == .fixed and e.work.after.len > 0) {
            if (earliest(entries, e, calendar)) |may| if (start < may) {
                try report.add(item.file, item.line, 1, "{s}: it starts on {s}, and its predecessors let it start on {s} at the earliest", .{ item.id, &day.format(start), &day.format(may) });
            };
        }
        for (e.work.parents) |id| {
            const parent = find(entries, id) orelse continue;
            // a parent that spans its children holds them all
            if (parent.mode == .float and parent.work.after.len == 0) continue;
            const ps = parent.start orelse continue;
            const pf = parent.finish orelse continue;
            if (start < ps or finish > pf) {
                try report.add(item.file, item.line, 1, "{s}: it runs from {s} to {s}, outside its parent {s} ({s} to {s})", .{ item.id, &day.format(start), &day.format(finish), id, &day.format(ps), &day.format(pf) });
            }
        }
        if (milestoneOf(project, e.work)) |m| {
            const target = graph.find(m) orelse continue;
            const milestone = find(entries, target.id) orelse continue;
            const due = milestone.finish orelse continue;
            if (finish > due) try report.add(item.file, item.line, 1, "{s}: it finishes on {s}, after its milestone {s} ({s})", .{ item.id, &day.format(finish), target.id, &day.format(due) });
        }
    }
    try checkStored(io, arena, root, project, entries, report);
}

fn find(entries: []schedule.Entry, id: []const u8) ?*schedule.Entry {
    for (entries) |*e| if (std.mem.eql(u8, e.work.item.id, id)) return e;
    return null;
}

/// The first day the predecessors of `e` let it start; null when one has no dates
fn earliest(entries: []schedule.Entry, e: *const schedule.Entry, calendar: *const Calendar) ?day.Day {
    var latest: ?day.Day = null;
    for (e.work.after) |id| {
        const f = (find(entries, id) orelse continue).finish orelse return null;
        if (latest == null or f > latest.?) latest = f;
    }
    return calendar.forward(calendar.next(latest orelse return null), e.work.lag);
}

/// The value of the item's milestone role, when its type has one
fn milestoneOf(project: *const Project, w: *const Work) ?[]const u8 {
    const t = project.schema.itemType(w.item.type_name) orelse return null;
    const attr = (t.planning orelse return null).attribute(.milestone) orelse return null;
    return w.item.attribute(attr);
}

/// Each stored file must be what `skein schedule` writes now
fn checkStored(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, entries: []const schedule.Entry, report: *Report) Error!void {
    try compare(io, arena, root, stored.toml_file, try stored.toml(arena, entries), report);
    for (project.schedule_also) |format| {
        const want = if (std.mem.eql(u8, format, "json")) try stored.json(arena, entries) else try stored.csv(arena, entries);
        try compare(io, arena, root, stored.fileOf(format), want, report);
    }
}

fn compare(io: Io, arena: std.mem.Allocator, root: Io.Dir, file: []const u8, want: []const u8, report: *Report) Error!void {
    const have = root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return report.add(file, 0, 0, "there is no stored schedule of the work items here: run 'skein schedule'", .{}),
    };
    // a checkout may have turned the line ends into CRLF
    const lf = try std.mem.replaceOwned(u8, arena, have, "\r\n", "\n");
    if (!std.mem.eql(u8, lf, want)) try report.add(file, 0, 0, "the stored schedule is not the one the work items give now: run 'skein schedule'", .{});
}
