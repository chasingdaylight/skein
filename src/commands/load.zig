//! `skein load`: each person's work, week by week, beside the time they
//! have (`.skein/resources.toml`).

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Json = @import("../output/Json.zig");
const Resources = @import("../planning/Resources.zig");
const Workspace = @import("Workspace.zig");
const day = @import("../planning/day.zig");
const planning_forge = @import("../planning/forge.zig");
const planning_load = @import("../planning/load.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Load) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const before = ws.report.problems.items.len;
    const resources = try Resources.of(io, arena, &ws, &ws.report) orelse return .{
        .text = try arena.print("skein: the project has no {s}, which lists the people who do the work\n", .{Resources.file}),
        .status = .misuse,
    };
    if (ws.report.problems.items.len > before) return ws.problems();
    const works = (try planning_forge.collect(io, arena, ws.root, &ws.project, &ws.graph, options.common.offline)).works;
    const loads = try planning_load.compute(arena, works, &resources);

    if (options.json) {
        var j: Json = .{ .arena = arena };
        try j.beginObject();
        try j.key("people");
        try j.beginArray();
        for (loads) |l| {
            try j.beginObject();
            try j.key("handle");
            try j.string(l.person.handle);
            try j.key("name");
            try j.string(l.person.name);
            try j.key("weeks");
            try j.beginArray();
            for (l.weeks) |w| {
                try j.beginObject();
                try j.key("week");
                try j.string(&day.isoWeek(w.monday));
                try j.key("monday");
                try j.string(&day.format(w.monday));
                try j.key("hours");
                try j.tenths(w.hours);
                try j.key("capacity");
                try j.tenths(w.capacity);
                try j.endObject();
            }
            try j.endArray();
            try j.endObject();
        }
        try j.endArray();
        try j.endObject();
        return .{ .text = try j.finish() };
    }
    var out: std.ArrayList(u8) = .empty;
    for (loads, 0..) |l, i| {
        if (i > 0) try out.append(arena, '\n');
        try out.print(arena, "{s}", .{l.person.handle});
        if (l.person.name.len > 0) try out.print(arena, " ({s})", .{l.person.name});
        try out.append(arena, '\n');
        if (l.weeks.len == 0) try out.appendSlice(arena, "  no work with dates\n");
        for (l.weeks) |w| {
            try out.print(arena, "  {s}  {s}  {d:>6.1} h of {d:>5.1} h", .{ &day.isoWeek(w.monday), &day.format(w.monday), w.hours, w.capacity });
            if (w.over()) try out.print(arena, "  over by {d:.1} h", .{w.hours - w.capacity});
            try out.append(arena, '\n');
        }
    }
    if (loads.len == 0) try out.print(arena, "No one is listed in {s}.\n", .{Resources.file});
    return .{ .text = out.items };
}
