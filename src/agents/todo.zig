//! What is still to do in a project, for the agent (or person) setting it
//! up (#265): template options not given, no citation sets, no milestone,
//! documents still the template's skeletons, templates brought along
//! without their documents, and no CI job that runs `skein check`.
//! `skein agents` writes it into the instructions, and `skein init` says it.

const std = @import("std");
const Io = std.Io;

const Template = @import("../template/Template.zig");
const git = @import("../git.zig");
const Workspace = @import("../commands/Workspace.zig");

/// A line each, without a list marker; none when the project is set up
pub fn list(io: Io, arena: std.mem.Allocator, ws: *const Workspace) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (ws.report.problems.items) |p| {
        if (std.mem.find(u8, p.message, "needs the option") != null) try out.append(arena, try arena.print("Give the template's option in `.skein/config.toml`: {s}.", .{p.message}));
    }
    const project = &ws.project;
    if (project.citations.len == 0) try out.append(arena, "Say where the tests and the code are (`[[citations]]` in `.skein/config.toml`, often there as comments to fill in), so that `skein coverage` counts what cites the requirements.");
    if (project.maturity.order.len > 0 and project.maturity.milestone == null) try out.append(arena, "Set `[maturity] milestone` to the review the project is at next, so that `skein check` holds the documents to the maturity it expects.");
    var skeletons: std.ArrayList([]const u8) = .empty;
    for (project.templates) |u| {
        var any = false;
        for (try Template.filesOf(arena, u.name, "documents/")) |f| {
            const path = try arena.print("docs/{s}", .{f.path["documents/".len..]});
            const have = ws.root.readFileAlloc(io, path, arena, .limited(1 << 24)) catch continue;
            any = true;
            if (std.mem.eql(u8, have, try Template.substitute(arena, f.data, u.options))) try skeletons.append(arena, path);
        }
        if (u.brought_by) |by| if (!any and (try Template.filesOf(arena, u.name, "documents/")).len > 0) {
            try out.append(arena, try arena.print("Write the documents of `{s}`, which `{s}` brings along: `skein template documents`.", .{ u.name, by }));
        };
    }
    if (skeletons.items.len > 0) {
        const shown = skeletons.items[0..@min(skeletons.items.len, 6)];
        try out.append(arena, try arena.print("Fill in the documents that are still the template's skeletons ({d}: {s}{s}), or remove those the project's tailoring leaves out.", .{ skeletons.items.len, try std.mem.join(arena, ", ", shown), if (skeletons.items.len > shown.len) ", ..." else "" }));
    }
    if (!try hasCi(io, arena, ws.root)) try out.append(arena, "Add a CI job that runs `skein check` and `skein coverage` (see \"In continuous integration\" in Skein's `docs/commands.md`).");
    return out.items;
}

/// Whether a GitHub, GitLab or Forgejo workflow of the project, or of the
/// repository it is in, runs skein
fn hasCi(io: Io, arena: std.mem.Allocator, root: Io.Dir) !bool {
    if (try runsSkein(io, arena, root)) return true;
    // a project in a directory git ignores is not the repository's
    if (try git.output(io, arena, root, &.{ "check-ignore", "-q", "." }) != null) return false;
    const top_out = try git.output(io, arena, root, &.{ "rev-parse", "--show-toplevel" }) orelse return false;
    var top = Io.Dir.cwd().openDir(io, std.mem.trim(u8, top_out, " \r\n"), .{}) catch return false;
    defer top.close(io);
    return runsSkein(io, arena, top);
}

fn runsSkein(io: Io, arena: std.mem.Allocator, root: Io.Dir) !bool {
    if (root.readFileAlloc(io, ".gitlab-ci.yml", arena, .limited(1 << 22))) |text| {
        if (std.mem.find(u8, text, "skein") != null) return true;
    } else |_| {}
    for ([_][]const u8{ ".github/workflows", ".forgejo/workflows", ".gitea/workflows" }) |dir_path| {
        var dir = root.openDir(io, dir_path, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |entry| {
            if (entry.kind != .file) continue;
            const text = dir.readFileAlloc(io, entry.name, arena, .limited(1 << 22)) catch continue;
            if (std.mem.find(u8, text, "skein") != null) return true;
        }
    }
    return false;
}
