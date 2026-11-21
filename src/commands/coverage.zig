//! `skein coverage`: of the items that should be linked to or cited, how
//! many are, and which are not.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Json = @import("../output/Json.zig");
const Workspace = @import("Workspace.zig");
const coverage = @import("../graph/coverage.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Coverage) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return .{
        .text = try arena.print("skein: there is no profile '{s}'\n", .{name}),
        .status = .misuse,
    } else null;
    const expectations = try coverage.compute(arena, &ws.project, &ws.graph, &ws.citations, profile);

    if (options.json) {
        var j: Json = .{ .arena = arena };
        try j.beginObject();
        try j.key("profile");
        try j.optional(options.profile);
        try j.key("expectations");
        try j.beginArray();
        for (expectations) |e| {
            try j.beginObject();
            try j.key("kind");
            try j.string(@tagName(e.kind));
            try j.key("name");
            try j.string(e.name);
            try j.key("type");
            try j.string(e.item_type);
            try j.key("total");
            try j.integer(@intCast(e.total));
            try j.key("covered");
            try j.integer(@intCast(e.covered));
            try j.key("categories");
            try j.beginArray();
            for (e.categories) |c| {
                try j.beginObject();
                try j.key("category");
                try j.string(c.name);
                try j.key("total");
                try j.integer(@intCast(c.total));
                try j.key("covered");
                try j.integer(@intCast(c.covered));
                try j.endObject();
            }
            try j.endArray();
            try j.key("uncovered");
            try j.strings(e.uncovered);
            try j.endObject();
        }
        try j.endArray();
        try j.endObject();
        return .{ .text = try j.finish() };
    }

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "Coverage of {s}", .{ws.name()});
    if (options.profile) |name| try out.print(arena, ", profile {s}", .{name});
    try out.appendSlice(arena, "\n");
    if (expectations.len == 0) {
        try out.appendSlice(arena, "\nNothing is expected: no link type and no citation set has 'expected = true'.\n");
    }
    for (expectations) |e| {
        const what = switch (e.kind) {
            .link => "links to",
            .citation => "citations of",
        };
        try out.print(arena, "\n{s} {s} {s} items: ", .{ e.name, what, e.item_type });
        try ratio(arena, &out, e.covered, e.total);
        try out.append(arena, '\n');
        for (e.categories) |c| {
            if (c.total == 0) continue;
            try out.print(arena, "  {s}: ", .{c.name});
            try ratio(arena, &out, c.covered, c.total);
            try out.append(arena, '\n');
        }
        if (e.uncovered.len > 0) try out.appendSlice(arena, "  without:\n");
        for (e.uncovered) |id| try out.print(arena, "    {s}\n", .{id});
    }
    return .{ .text = out.items };
}

/// "12 of 15 (80%)"
fn ratio(arena: std.mem.Allocator, out: *std.ArrayList(u8), covered: usize, total: usize) !void {
    try out.print(arena, "{d} of {d}", .{ covered, total });
    if (total > 0) try out.print(arena, " ({d}%)", .{covered * 100 / total});
}
