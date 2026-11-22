//! `skein trace ID`: an item with everything above and below it.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Json = @import("../output/Json.zig");
const Approvals = @import("../graph/Approvals.zig");
const Results = @import("../results/Results.zig");
const Reviews = @import("../graph/Reviews.zig");
const Workspace = @import("Workspace.zig");
const describe = @import("../output/describe.zig");
const walk = @import("../graph/walk.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Trace) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    // an item can be traced while others have problems; the schema must be sound
    if (!ws.items_read) return ws.problems();

    const item = ws.graph.find(options.id) orelse return .{
        .text = try arena.print("skein: there is no item '{s}'\n", .{options.id}),
        .status = .misuse,
    };
    var ignored: @import("../Report.zig") = .{ .arena = arena };
    const reviews = try Reviews.load(io, arena, ws.root, &ignored);
    const approvals = try Approvals.load(io, arena, ws.root, &ignored);
    // results that cannot be read are the command's to report
    const before = ws.report.problems.items.len;
    const results = try Results.load(io, arena, ws.root, &ws.project, options.results, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const idx = try results.index(arena, &ws.graph, &ws.citations);
    const mine: []const usize = if (idx.by_item.get(item.id)) |l| l.items else &.{};
    const ctx: describe.Context = .{
        .arena = arena,
        .project = &ws.project,
        .graph = &ws.graph,
        .citations = &ws.citations,
        .reviews = &reviews,
        .approvals = &approvals,
    };

    if (options.json) {
        var j: Json = .{ .arena = arena };
        try j.beginObject();
        try j.key("item");
        try describe.json(ctx, &j, item, true);
        try j.key("above");
        try j.strings(try walk.reach(arena, &ws.graph, item.id, .above));
        try j.key("below");
        try j.strings(try walk.reach(arena, &ws.graph, item.id, .below));
        try j.key("results");
        try j.beginArray();
        for (try results.implementations(arena)) |implementation| {
            try j.beginObject();
            try j.key("implementation");
            try j.string(implementation);
            try j.key("verdict");
            try j.string(@tagName(results.verdict(&idx, item.id, implementation)));
            try j.key("results");
            try j.beginArray();
            for (mine) |i| {
                const r = results.all[i];
                if (!std.mem.eql(u8, r.implementation, implementation)) continue;
                try j.beginObject();
                try j.key("test");
                try j.string(r.label());
                try j.key("result");
                try j.string(@tagName(r.outcome));
                try j.key("source");
                try j.string(r.source);
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
    try describe.text(ctx, &out, item);
    if (mine.len > 0) try out.appendSlice(arena, "\nResults:\n");
    for (try results.implementations(arena)) |implementation| {
        if (mine.len == 0) break;
        try out.print(arena, "  {s}: {s}\n", .{ try results.implementationName(arena, implementation), @tagName(results.verdict(&idx, item.id, implementation)) });
        for (mine) |i| {
            const r = results.all[i];
            if (!std.mem.eql(u8, r.implementation, implementation)) continue;
            try out.print(arena, "    {s}  {s}  ({s}, result {d})\n", .{ @tagName(r.outcome), r.label(), r.source, r.index });
        }
    }
    return .{ .text = out.items };
}
