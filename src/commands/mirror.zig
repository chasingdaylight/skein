//! `skein mirror`: copies everything the forge holds of the project's issues,
//! pull requests, milestones and labels into `.skein/mirror/`, in plain text,
//! for working offline and for `skein publish`. The mirror is per checkout
//! (git ignores it) unless the configuration says `mirror = "committed"`.

const std = @import("std");
const Io = std.Io;

const Mirror = @import("../forge/Mirror.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const fetch = @import("../forge/mirror_fetch.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Mirror) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    return mirror(io, arena, &ws, options.common.offline);
}

/// Mirrors the forge of the open project
pub fn mirror(io: Io, arena: std.mem.Allocator, ws: *Workspace, offline: bool) !Workspace.Outcome {
    const forge = ws.project.forge orelse return misuse(arena, "the project names no forge: nothing to mirror", .{});
    if (offline) return misuse(arena, "mirroring reads the forge: not with --offline", .{});
    const data = switch (try fetch.fetch(io, arena, &forge)) {
        .data => |d| d,
        .failed => |why| return misuse(arena, "the forge could not be read: {s}", .{why}),
    };
    try Mirror.save(io, arena, ws.root, data, forge.mirror_committed);
    var issues: usize = 0;
    var pulls: usize = 0;
    for (data.issues) |i| {
        if (i.pull) pulls += 1 else issues += 1;
    }
    return .{ .text = try arena.print("skein: mirrored {d} issue{s}, {d} pull or merge request{s}, {d} milestone{s} and {d} label{s} of {s} into {s}/ ({s})\n", .{
        issues,
        if (issues == 1) "" else "s",
        pulls,
        if (pulls == 1) "" else "s",
        data.milestones.len,
        if (data.milestones.len == 1) "" else "s",
        data.labels.len,
        if (data.labels.len == 1) "" else "s",
        forge.repository,
        Mirror.dir,
        if (forge.mirror_committed) "to be committed" else "ignored by git",
    }) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
