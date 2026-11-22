//! `skein time ITEM HOURS`: logs time spent on a work item, by a person on
//! a day, with a note. `skein time` alone sets what was spent against the
//! estimate of each work item that has either.

const std = @import("std");
const Io = std.Io;

const Json = @import("../output/Json.zig");
const Resources = @import("../planning/Resources.zig");
const Time = @import("../planning/Time.zig");
const Workspace = @import("Workspace.zig");
const approve = @import("approve.zig");
const cli = @import("../cli.zig");
const git = @import("../git.zig");
const planning_forge = @import("../planning/forge.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.TimeSpent) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const before = ws.report.problems.items.len;
    var time = try Time.load(io, arena, ws.root, &ws.report);
    const resources = try Resources.of(io, arena, &ws, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const works = (try planning_forge.collect(io, arena, ws.root, &ws.project, &ws.graph, options.common.offline)).works;
    if (works.len == 0) return misuse(arena, "there are no work items: no item type has [planning]", .{});

    const hours_a_day = if (resources) |r| r.calendar.hours else 8;
    const id = options.id orelse return report(arena, try Time.summarize(arena, works, time.all.items, hours_a_day), options.json);

    const item = ws.graph.find(id) orelse return misuse(arena, "there is no item '{s}'", .{id});
    if (@import("../planning/Work.zig").find(works, item.id) == null) return misuse(arena, "{s} is no work item", .{item.id});
    if (ws.project.readOnlySource(item.file)) |s| return misuse(arena, "{s} is in the read-only source '{s}'", .{ item.id, s.path });
    const text = options.hours orelse return misuse(arena, "say how many hours", .{});
    const hours = std.fmt.parseFloat(f64, text) catch return misuse(arena, "'{s}' is no number of hours", .{text});
    if (!(hours > 0) or hours > Time.max_hours_a_day) return misuse(arena, "hours are more than 0 and at most {d}", .{@as(u32, Time.max_hours_a_day)});
    const by = options.by orelse try git.userName(io, arena, ws.root) orelse return misuse(arena, "who spent it? Give --by NAME (git has no user.name to take it from)", .{});
    const on = if (options.on) |d| approve.parseDate(d) orelse return misuse(arena, "'{s}' is no date; write it like 2027-03-01", .{d}) else approve.today(io);
    const on_text = try arena.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ on.year, on.month, on.day });

    const file = try Time.fileOf(arena, item);
    switch (try time.log(io, arena, ws.root, file, item.id, by, on_text, hours, options.note)) {
        .refused => |why| return misuse(arena, "{s}", .{why}),
        .total => |day_total| return .{ .text = try arena.print("skein: {s} has {d} hours of {s} on {s}, in {s}\n", .{ item.id, day_total, by, on_text, file }) },
    }
}

fn report(arena: std.mem.Allocator, rows: []const Time.Row, as_json: bool) !Workspace.Outcome {
    if (as_json) {
        var j: Json = .{ .arena = arena };
        try j.beginArray();
        for (rows) |r| {
            try j.beginObject();
            try j.key("item");
            try j.string(r.work.item.id);
            try j.key("estimate");
            if (r.estimate) |e| try j.tenths(e) else try j.optional(null);
            try j.key("spent");
            try j.tenths(r.spent);
            try j.key("by");
            try j.beginArray();
            for (r.by) |b| {
                try j.beginObject();
                try j.key("name");
                try j.string(b.name);
                try j.key("hours");
                try j.tenths(b.hours);
                try j.endObject();
            }
            try j.endArray();
            try j.endObject();
        }
        try j.endArray();
        return .{ .text = try j.finish() };
    }
    if (rows.len == 0) return .{ .text = "No work item has an estimate or time spent.\n" };
    var out: std.ArrayList(u8) = .empty;
    var estimate: f64 = 0;
    var spent: f64 = 0;
    for (rows) |r| {
        try out.print(arena, "{s}  ", .{r.work.item.id});
        if (r.estimate) |e| try out.print(arena, "estimate {d:.1} h  ", .{e}) else try out.appendSlice(arena, "no estimate    ");
        try out.print(arena, "spent {d:.1} h", .{r.spent});
        if (r.estimate) |e| {
            try out.print(arena, "  ({s}{d:.1} h)", .{ if (r.spent > e) "+" else "", r.spent - e });
            estimate += e;
        }
        spent += r.spent;
        for (r.by, 0..) |b, i| try out.print(arena, "{s}{s} {d:.1}", .{ if (i == 0) "  by " else ", ", b.name, b.hours });
        try out.append(arena, '\n');
    }
    try out.print(arena, "\nIn all: estimate {d:.1} h, spent {d:.1} h\n", .{ estimate, spent });
    return .{ .text = out.items };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
