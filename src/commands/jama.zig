//! `skein jama [--profile NAME] [--dry-run]`: a Jama Connect project's items
//! brought to the items through Jama's REST API (forge/jama_publish.zig),
//! as `.skein/jama.toml` says, and the map of `.skein/jama-map.toml` kept
//! with them.

const std = @import("std");
const Io = std.Io;

const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const config = @import("../forge/jama_config.zig");
const coverage = @import("../graph/coverage.zig");
const jama = @import("../forge/jama.zig");
const publish = @import("../forge/jama_publish.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.GitlabRequirements) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const c = switch (try config.load(io, arena, ws.root)) {
        .ok => |c| c,
        .missing => return misuse(arena, "say which Jama project, and which item types go to it, in {s} (see Skein's docs/forge.md, \"Jama Connect\")", .{config.config_file}),
        .failed => |why| return misuse(arena, "{s}", .{why}),
    };
    for (c.types) |t| if (ws.project.schema.itemType(t.name) == null) return misuse(arena, "{s}: the project has no item type '{s}'", .{ config.config_file, t.name });
    for (c.links) |l| if (ws.project.schema.linkType(l.name) == null) return misuse(arena, "{s}: the project has no link type '{s}'", .{ config.config_file, l.name });
    if (c.types.len == 0) return misuse(arena, "{s}: name the item types that go to Jama, under [types]", .{config.config_file});
    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return misuse(arena, "there is no profile '{s}'", .{name}) else null;

    var wanted: std.ArrayList(publish.Wanted) = .empty;
    for (ws.graph.items) |*item| {
        const type_id = c.typeId(item.type_name) orelse continue;
        const t = ws.project.schema.itemType(item.type_name) orelse continue;
        if (profile) |p| if (!coverage.inProfile(p, item, t)) continue;
        try wanted.append(arena, .{ .item = item, .type_id = type_id, .removed = item.isTombstone(t) });
    }
    const client = switch (try jama.connect(io, arena, c.url)) {
        .found => |cl| cl,
        .missing => unreachable,
        .failed => |why| return .{ .text = try arena.print("skein: {s}\n", .{why}), .status = .problems },
    };
    const map = try config.loadMap(io, arena, ws.root);
    const done = switch (try publish.publish(arena, &client, c, wanted.items, map, options.dry_run)) {
        .done => |d| d,
        .failed => |why| return .{ .text = try arena.print("skein: {s}\n", .{why}), .status = .problems },
    };

    var out: std.ArrayList(u8) = .empty;
    var counts: std.EnumArray(publish.Kind, usize) = .initFill(0);
    for (done.actions) |a| {
        counts.getPtr(a.kind).* += 1;
        switch (a.kind) {
            .same => {},
            .created => if (a.jama == 0) try out.print(arena, "{s}: created\n", .{a.id}) else try out.print(arena, "{s}: created (Jama item {d})\n", .{ a.id, a.jama }),
            .updated => try out.print(arena, "{s}: updated (Jama item {d}, which said otherwise)\n", .{ a.id, a.jama }),
            .removed => try out.print(arena, "{s}: removed here; Jama item {d} is left for its owners to delete\n", .{ a.id, a.jama }),
        }
    }
    var added: usize = 0;
    for (done.relationships) |r| switch (r.kind) {
        .added => {
            added += 1;
            try out.print(arena, "{s} {s} {s}: relationship added\n", .{ r.from, r.link, r.to });
        },
        .only_in_jama => try out.print(arena, "{s} {s} {s}: in Jama only; link it here, or take it out of Jama\n", .{ r.from, r.link, r.to }),
    };
    if (!options.dry_run) try config.saveMap(io, arena, ws.root, done.entries);
    try out.print(arena, "skein: {s}{d} created, {d} updated, {d} removed here, {d} as they are, {d} relationship{s} added", .{
        if (options.dry_run) "would be: " else "",
        counts.get(.created),
        counts.get(.updated),
        counts.get(.removed),
        counts.get(.same),
        added,
        if (added == 1) "" else "s",
    });
    try out.appendSlice(arena, if (options.dry_run) "; nothing written\n" else try arena.print("; the map is in {s}\n", .{config.map_file}));
    return .{ .text = out.items };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
