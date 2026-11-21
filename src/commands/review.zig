//! `skein review` and `skein clear`: record that links have been
//! reviewed against their targets as they are now.
//!
//! - `review ID...`: the links of these items (I have looked at my item
//!   against what it points to).
//! - `clear ID...`: the links to these items (this item changed, and I
//!   have looked at everything that points to it).

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Reviews = @import("../graph/Reviews.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const fingerprint = @import("../graph/fingerprint.zig");

pub const Direction = enum {
    /// the links of the items named
    from,
    /// the links to the items named
    to,
};

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Review, direction: Direction) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    // what is wrong with the items is for `check`; the schema must be sound
    if (!ws.items_read) return ws.problems();

    for (options.ids) |id| {
        if (ws.graph.find(id) == null) return .{
            .text = try arena.print("skein: there is no item '{s}'\n", .{id}),
            .status = .misuse,
        };
    }

    const schema = &ws.project.schema;
    // the records must be readable, or writing them again would lose some
    const before = ws.report.problems.items.len;
    var reviews = try Reviews.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();

    var files: std.ArrayList([]const u8) = .empty;
    var count: usize = 0;
    for (ws.graph.items) |*item| {
        for (item.links) |link| {
            const named = options.all or Schema.names.contains(options.ids, switch (direction) {
                .from => item.id,
                .to => link.target,
            });
            if (!named) continue;
            const state = try reviews.stateOf(arena, schema, &ws.graph, item, link) orelse continue;
            if (state == .reviewed) continue;
            const target = ws.graph.find(link.target).?;
            const fp = try fingerprint.of(arena, &ws.graph, schema, target);
            try reviews.put(arena, item.id, link.type_name, link.target, &fp);
            const file = try Reviews.fileOf(arena, item);
            if (!Schema.names.contains(files.items, file)) try files.append(arena, file);
            count += 1;
        }
    }
    try reviews.write(io, arena, ws.root, schema, &ws.graph, files.items);
    return .{
        .text = try arena.print("skein: {d} link{s} recorded as reviewed\n", .{ count, if (count == 1) "" else "s" }),
    };
}
