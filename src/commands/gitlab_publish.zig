//! `skein gitlab-requirements [--profile NAME] [--dry-run]`: GitLab's
//! requirements brought to the items through GitLab's API
//! (forge/gitlab_publish.zig), and the map of `.skein/gitlab-requirements.toml`
//! kept with them. The project's forge is GitLab (`[forge] kind = "gitlab"`).

const std = @import("std");
const Io = std.Io;

const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const coverage = @import("../graph/coverage.zig");
const history = @import("../history.zig");
const publish = @import("../forge/gitlab_publish.zig");
const requirements = @import("../forge/gitlab_requirements.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.GitlabRequirements) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const forge = ws.project.forge orelse return misuse(arena, "the project names no forge: [forge] kind = \"gitlab\" in .skein/config.toml", .{});
    if (forge.kind != .gitlab) return misuse(arena, "the project's forge is {t}, not GitLab", .{forge.kind});
    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return misuse(arena, "there is no profile '{s}'", .{name}) else null;

    var wanted: std.ArrayList(publish.Wanted) = .empty;
    for (ws.graph.items) |*item| {
        const t = ws.project.schema.itemType(item.type_name) orelse continue;
        if (profile) |p| if (!coverage.inProfile(p, item, t)) continue;
        try wanted.append(arena, .{ .item = item, .removed = item.isTombstone(t) });
    }
    const map = try requirements.loadMap(io, arena, ws.root);
    // the request is written in git's directory, never in the project
    const git_dir = history.gitDir(io, arena, ws.root) catch try arena.dupe(u8, ".");
    const body_path = try Io.Dir.path.join(arena, &.{ git_dir, "skein", "forge", "graphql.json" });
    const outcome = try publish.publish(io, arena, &forge, wanted.items, map, options.dry_run, body_path);
    const done = switch (outcome) {
        .done => |d| d,
        .failed => |why| return .{ .text = try arena.print("skein: {s}\n", .{why}), .status = .problems },
    };

    var out: std.ArrayList(u8) = .empty;
    var counts: std.EnumArray(publish.Kind, usize) = .initFill(0);
    for (done.actions) |a| {
        counts.getPtr(a.kind).* += 1;
        if (a.kind == .same) continue;
        if (a.iid == 0) try out.print(arena, "{s}: {t}\n", .{ a.id, a.kind }) else try out.print(arena, "{s}: {t} (requirement {d})\n", .{ a.id, a.kind, a.iid });
    }
    if (!options.dry_run) try requirements.saveMap(io, arena, ws.root, done.entries);
    try out.print(arena, "skein: {s}{d} created, {d} updated, {d} reopened, {d} archived, {d} as they are", .{
        if (options.dry_run) "would be: " else "",
        counts.get(.created),
        counts.get(.updated),
        counts.get(.reopened),
        counts.get(.archived),
        counts.get(.same),
    });
    try out.appendSlice(arena, if (options.dry_run) "; nothing written\n" else try arena.print("; the map is in {s}\n", .{requirements.map_file}));
    return .{ .text = out.items };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
