//! `skein trace ID`: an item with everything above and below it.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Json = @import("../output/Json.zig");
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
    const ctx: describe.Context = .{
        .arena = arena,
        .project = &ws.project,
        .graph = &ws.graph,
        .citations = &ws.citations,
        .reviews = &reviews,
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
        try j.endObject();
        return .{ .text = try j.finish() };
    }
    var out: std.ArrayList(u8) = .empty;
    try describe.text(ctx, &out, item);
    return .{ .text = out.items };
}
