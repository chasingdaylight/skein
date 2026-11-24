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
const Graph = @import("../graph/Graph.zig");
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
        // `review` also takes the files that cite items
        if (ws.graph.find(id) == null and !(direction == .from and citesIn(&ws.citations, id))) return .{
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
            const fp = (try Reviews.targetFingerprint(arena, schema, &ws.graph, link.target)).?;
            try reviews.put(arena, item.id, link.type_name, link.target, &fp);
            const file = try Reviews.fileOf(arena, item);
            if (!Schema.names.contains(files.items, file)) try files.append(arena, file);
            count += 1;
        }
    }
    try reviews.write(io, arena, ws.root, schema, &ws.graph, files.items);

    // the citations of the sets that are reviewed: those in the files named, or of the items named
    var cite_files: std.ArrayList([]const u8) = .empty;
    var cited: usize = 0;
    for (ws.citations.all) |c| {
        const named = options.all or Schema.names.contains(options.ids, switch (direction) {
            .from => c.file,
            .to => c.target,
        });
        if (!named) continue;
        const state = try reviews.citationState(arena, &ws.project, &ws.graph, c) orelse continue;
        if (state == .reviewed) continue;
        const fp = (try Reviews.targetFingerprint(arena, schema, &ws.graph, c.target)).?;
        try reviews.putCitation(arena, c, &fp);
        const file = try Reviews.citationFileOf(arena, c.file);
        if (!Schema.names.contains(cite_files.items, file)) try cite_files.append(arena, file);
        cited += 1;
    }
    try reviews.writeCitations(io, arena, ws.root, &ws.project, &ws.citations, cite_files.items);
    return .{
        .text = if (cited == 0)
            try arena.print("skein: {d} link{s} recorded as reviewed\n", .{ count, if (count == 1) "" else "s" })
        else
            try arena.print("skein: {d} link{s} and {d} citation{s} recorded as reviewed\n", .{ count, if (count == 1) "" else "s", cited, if (cited == 1) "" else "s" }),
    };
}

/// Whether some citation is in the file `path`
fn citesIn(citations: *const Graph.Citations, path: []const u8) bool {
    for (citations.all) |c| if (std.mem.eql(u8, c.file, path)) return true;
    return false;
}
