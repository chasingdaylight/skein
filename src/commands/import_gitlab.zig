//! `skein import gitlab-requirements FILE`: the GitLab requirement of each
//! item, from the CSV GitLab exports of a project's requirements, recorded
//! in `.skein/gitlab-requirements.toml` for `coverage --gitlab-requirements`.
//! A requirement belongs to the item whose ID starts its title, as
//! `export gitlab-requirements` writes them.

const std = @import("std");
const Io = std.Io;

const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const requirements = @import("../forge/gitlab_requirements.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Import) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const path = options.paths[0];
    const text = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 26)) catch |e|
        return misuse(arena, "cannot read '{s}' ({s})", .{ path, @errorName(e) });
    const matched = try requirements.matchExport(arena, text, &ws.graph) orelse
        return misuse(arena, "'{s}' is not a CSV of GitLab's requirements: it needs the columns 'Requirement ID' and 'Title'", .{path});
    requirements.saveMap(io, arena, ws.root, matched.entries) catch |e|
        return misuse(arena, "cannot write {s} ({s})", .{ requirements.map_file, @errorName(e) });

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "skein: recorded the GitLab requirements of {d} item{s} in {s}\n", .{ matched.entries.len, if (matched.entries.len == 1) "" else "s", requirements.map_file });
    if (matched.unmatched.len > 0) {
        try out.print(arena, "{d} {s} no item:\n", .{ matched.unmatched.len, if (matched.unmatched.len == 1) "requirement names" else "requirements name" });
        for (matched.unmatched) |t| try out.print(arena, "  {s}\n", .{t});
    }
    return .{ .text = out.items };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
