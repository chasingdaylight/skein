//! `skein check`: what is wrong with the project.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Graph = @import("../graph/Graph.zig");
const Results = @import("../results/Results.zig");
const Reviews = @import("../graph/Reviews.zig");
const Workspace = @import("Workspace.zig");
const network_checks = @import("../network/checks.zig");

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
        .text = try arena.print("{s}skein: {s}: no problems{s} ({d} items of {d} types, {d} link types, {d} profiles, {d} citations)\n", .{
            try ws.report.render(arena), ws.name(),            try ws.warningCount(), ws.graph.items.len, schema.types.len, schema.links.len,
            schema.profiles.len,         ws.citations.all.len,
        }),
    };
}

/// `check` in the format `options` asks for: as text, or for a CI system
/// to show on the lines of a change
pub fn runFormatted(io: Io, arena: std.mem.Allocator, options: cli.Check) !Workspace.Outcome {
    if (options.format == .text) return run(io, arena, options.common);
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    try all(io, arena, &ws);
    return .{
        .text = switch (options.format) {
            .text => unreachable,
            .github => try ws.report.renderGithub(arena),
            .gitlab => try ws.report.renderGitlab(arena),
        },
        .status = if (ws.report.ok()) .ok else .problems,
        .to_stdout = true,
    };
}

/// Adds to the report of `ws` everything that is wrong with the project.
/// When the configuration or the schema has problems, the items were not
/// read and only those problems are in it.
pub fn all(io: Io, arena: std.mem.Allocator, ws: *Workspace) !void {
    if (!ws.report.ok()) return;
    try Graph.checks.run(&ws.graph, &ws.project.schema, &ws.report);
    try ws.citations.check(&ws.project, &ws.graph, &ws.report);
    try network_checks.run(arena, &ws.project, &ws.graph, &ws.citations, &ws.network, &ws.report);
    const reviews = try Reviews.load(io, arena, ws.root, &ws.report);
    const approvals = try Graph.Approvals.load(io, arena, ws.root, &ws.report);
    try approvals.check(arena, &ws.project.schema, &ws.graph, &ws.report);
    try reviews.check(arena, &ws.project.schema, &ws.graph, &ws.report);
    // the results the project keeps: a result that belongs to no item is to be looked at
    const results = try Results.load(io, arena, ws.root, &ws.project, &ws.graph, &.{}, &ws.report);
    const idx = try results.index(arena, &ws.graph, &ws.citations);
    for (idx.unmatched) |i| {
        const r = results.all[i];
        try ws.report.warn(r.source, 0, 0, "result {d} ({s}) belongs to no item: no item cites its file, and it names none that exists", .{ r.index, r.label() });
    }
    for (results.all) |r| {
        const changed = r.stale orelse continue;
        try ws.report.warn(r.source, 0, 0, "result {d} ({s}) is stale: '{s}' has changed since it was recorded; record it again ('skein result')", .{ r.index, r.label(), changed });
    }
}
