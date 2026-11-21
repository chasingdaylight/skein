//! `skein check`: what is wrong with the project.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Graph = @import("../graph/Graph.zig");
const Reviews = @import("../graph/Reviews.zig");
const Workspace = @import("Workspace.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Common) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();

    if (ws.report.ok()) {
        try Graph.checks.run(&ws.graph, &ws.project.schema, &ws.report);
        const reviews = try Reviews.load(io, arena, ws.root, &ws.report);
        try reviews.check(arena, &ws.project.schema, &ws.graph, &ws.report);
    }
    if (!ws.report.ok()) return ws.problems();
    const schema = ws.project.schema;
    return .{
        .text = try arena.print("skein: {s}: no problems ({d} items of {d} types, {d} link types, {d} profiles)\n", .{
            ws.name(), ws.graph.items.len, schema.types.len, schema.links.len, schema.profiles.len,
        }),
    };
}
