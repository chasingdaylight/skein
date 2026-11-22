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

    try all(io, arena, &ws);
    if (!ws.report.ok()) return ws.problems();
    const schema = ws.project.schema;
    return .{
        .text = try arena.print("skein: {s}: no problems ({d} items of {d} types, {d} link types, {d} profiles, {d} citations)\n", .{
            ws.name(), ws.graph.items.len, schema.types.len, schema.links.len, schema.profiles.len, ws.citations.all.len,
        }),
    };
}

/// Adds to the report of `ws` everything that is wrong with the project.
/// When the configuration or the schema has problems, the items were not
/// read and only those problems are in it.
pub fn all(io: Io, arena: std.mem.Allocator, ws: *Workspace) !void {
    if (!ws.report.ok()) return;
    try Graph.checks.run(&ws.graph, &ws.project.schema, &ws.report);
    try ws.citations.check(&ws.project, &ws.graph, &ws.report);
    const reviews = try Reviews.load(io, arena, ws.root, &ws.report);
    const approvals = try Graph.Approvals.load(io, arena, ws.root, &ws.report);
    try approvals.check(arena, &ws.project.schema, &ws.graph, &ws.report);
    try reviews.check(arena, &ws.project.schema, &ws.graph, &ws.report);
}
