//! `skein publish --to KIND:OWNER/REPO`: re-creates the mirror's labels,
//! milestones, issues and comments on another forge, through its adapter, and
//! keeps a map from the old references to the new ones in
//! `.skein/forge-map.toml`, which the project commits.

const std = @import("std");
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const ForgeMap = @import("../forge/Map.zig");
const Mirror = @import("../forge/Mirror.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const history = @import("../history.zig");
const publisher = @import("../forge/mirror_publish.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Publish) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    const to = options.to orelse return misuse(arena, "publish needs the forge to publish to: --to KIND:OWNER/REPO", .{});
    const target = parseTarget(to, options.url) orelse return misuse(arena, "'{s}' is no forge: write it KIND:OWNER/REPO, KIND github or gitlab", .{to});
    if (options.common.offline) return misuse(arena, "publishing writes to the forge: not with --offline", .{});
    const data = (try Mirror.load(io, arena, ws.root)) orelse return misuse(arena, "there is no mirror to publish: run 'skein mirror' first", .{});
    const git_dir = history.gitDir(io, arena, ws.root) catch return misuse(arena, "this is no git repository", .{});
    const body_path = try Io.Dir.path.join(arena, &.{ git_dir, "skein", "forge", "publish.json" });

    const done = try publisher.publish(io, arena, data, &target, body_path, options.dry_run);
    if (!options.dry_run and done.map.len > 0) {
        const moved = try arena.alloc(Forge.Moved, done.map.len);
        for (done.map, moved) |m, *out| out.* = .{ .from = m.from, .to = m.to };
        try ForgeMap.save(io, arena, ws.root, moved);
    }
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "skein: {s} {d} label{s}, {d} milestone{s}, {d} issue{s} and {d} comment{s} on {s}:{s}", .{
        if (options.dry_run) "would create" else "created",
        done.labels,
        plural(done.labels),
        done.milestones,
        plural(done.milestones),
        done.issues,
        plural(done.issues),
        done.comments,
        plural(done.comments),
        @tagName(target.kind),
        target.repository,
    });
    if (done.skipped > 0) try out.print(arena, "; {d} pull or merge request{s} left out", .{ done.skipped, plural(done.skipped) });
    try out.append(arena, '\n');
    if (done.failed) |why| {
        try out.print(arena, "skein: stopped: {s}\n", .{why});
        return .{ .text = out.items, .status = .problems };
    }
    return .{ .text = out.items };
}

/// `kind:owner/repo` as a forge, with the server's address when it is not the public one
fn parseTarget(text: []const u8, url: ?[]const u8) ?Forge {
    const colon = std.mem.findScalar(u8, text, ':') orelse return null;
    const kind = std.meta.stringToEnum(Forge.Kind, text[0..colon]) orelse return null;
    if (kind == .forgejo) return null;
    const repository = text[colon + 1 ..];
    if (std.mem.findScalar(u8, repository, '/') == null) return null;
    return .{ .kind = kind, .repository = repository, .url = if (url) |u| std.mem.trimEnd(u8, u, "/") else null };
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
