//! What `skein check` holds work items to, before any schedule: dates that
//! agree with the duration, a fixed item with a start, a mode that is
//! `fixed` or `float`, no loop of predecessors or parents, and a length for
//! every item that others depend on.

const std = @import("std");

const Calendar = @import("Calendar.zig");
const Graph = @import("../graph/Graph.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");

const Error = std.mem.Allocator.Error;

pub fn run(arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, calendar: *const Calendar, report: *Report) Error!void {
    const works = try Work.collect(arena, schema, graph);
    for (works) |*w| try own(w, calendar, report);
    // a predecessor's finish is what the items after it are scheduled from
    var without_length: std.StringHashMapUnmanaged(void) = .empty;
    for (works) |*w| for (w.after) |id| {
        const before = Work.find(works, id) orelse continue;
        if (before.hasLength() or (try without_length.getOrPut(arena, id)).found_existing) continue;
        try report.add(before.item.file, before.item.line, 1, "{s}: '{s}' follows it, and it has no duration", .{ id, w.item.id });
    };
    for (works) |*w| {
        for (w.item.links) |link| {
            const role = (schema.linkType(link.type_name) orelse continue).planning orelse continue;
            if (role == .blocks) continue;
            const target = graph.find(link.target) orelse graph.formerly(link.target) orelse continue;
            if (Work.find(works, target.id) == null) {
                try report.add(w.item.file, if (link.line > 0) link.line else w.item.line, 1, "{s}: {s}: '{s}' is not a work item", .{ w.item.id, link.type_name, target.id });
            }
        }
    }
    try loops(arena, works, report, .after);
    try loops(arena, works, report, .parents);
}

/// The item's own values
fn own(w: *const Work, calendar: *const Calendar, report: *Report) Error!void {
    const item = w.item;
    if (w.written_mode != null and w.mode() == null) {
        try report.add(item.file, item.line, 1, "{s}: '{s}' is no scheduling mode: \"fixed\" or \"float\"", .{ item.id, w.written_mode.? });
    }
    if (w.mode() == .fixed and w.start == null) {
        try report.add(item.file, item.line, 1, "{s}: a fixed work item needs a start", .{item.id});
    }
    const start = w.start orelse return;
    const finish = w.finish orelse return;
    if (finish < start) {
        try report.add(item.file, item.line, 1, "{s}: it finishes ({s}) before it starts ({s})", .{ item.id, &day.format(finish), &day.format(start) });
        return;
    }
    const duration = w.duration orelse return;
    const expected = calendar.finishOf(start, duration);
    if (expected != finish) {
        try report.add(item.file, item.line, 1, "{s}: a start of {s} and a duration of {d} working days finish on {s}, not {s}", .{ item.id, &day.format(start), duration, &day.format(expected), &day.format(finish) });
    }
}

/// Reports each loop of `field` (predecessors or parents) once, at the
/// item of the loop that comes first
fn loops(arena: std.mem.Allocator, works: []Work, report: *Report, comptime field: enum { after, parents }) Error!void {
    // 0 not seen, 1 on the path being walked, 2 done
    const state = try arena.alloc(u8, works.len);
    @memset(state, 0);
    var path: std.ArrayList(usize) = .empty;
    for (0..works.len) |i| try walk(arena, works, state, &path, i, report, field);
}

fn walk(arena: std.mem.Allocator, works: []Work, state: []u8, path: *std.ArrayList(usize), i: usize, report: *Report, comptime field: anytype) Error!void {
    if (state[i] == 2) return;
    if (state[i] == 1) {
        // the loop: from where `i` is on the path to its end, and back to `i`
        const at = std.mem.findScalar(usize, path.items, i).?;
        var text: std.ArrayList(u8) = .empty;
        for (path.items[at..]) |j| try text.print(arena, "{s} -> ", .{works[j].item.id});
        try text.appendSlice(arena, works[i].item.id);
        const first = works[i].item;
        const what = if (field == .after) "predecessors" else "parents";
        try report.add(first.file, first.line, 1, "{s}: a loop of {s}: {s}", .{ first.id, what, text.items });
        return;
    }
    state[i] = 1;
    try path.append(arena, i);
    const next = if (field == .after) works[i].after else works[i].parents;
    for (next) |id| {
        const j = indexOf(works, id) orelse continue;
        try walk(arena, works, state, path, j, report, field);
    }
    _ = path.pop();
    state[i] = 2;
}

fn indexOf(works: []const Work, id: []const u8) ?usize {
    for (works, 0..) |w, i| if (std.mem.eql(u8, w.id, id)) return i;
    return null;
}
