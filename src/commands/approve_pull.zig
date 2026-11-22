//! `skein approve --from-pull-request N`: records the approvals a merged
//! pull request had in review. Every item whose content it changed (added,
//! or changed in what it says) is approved, as it was at the merge, by each
//! reviewer whose last review approved it, on the day it was merged.

const std = @import("std");
const Io = std.Io;

const Approvals = @import("../graph/Approvals.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const approve = @import("approve.zig");
const changes = @import("../graph/changes.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const pulls = @import("../forge/pulls.zig");

pub fn run(io: Io, arena: std.mem.Allocator, ws: *Workspace, number: u64) !Workspace.Outcome {
    const forge = ws.project.forge orelse return misuse(arena, "the project names no forge ([forge] in .skein/config.toml)", .{});
    const pull = switch (try pulls.get(io, arena, &forge, number)) {
        .pull => |p| p,
        .missing => return misuse(arena, "{s} has no pull request {d}", .{ forge.repository, number }),
        .unreachable_ => |why| return misuse(arena, "the forge could not be asked: {s}", .{why}),
    };
    const merged_on = pull.merged_on orelse return misuse(arena, "pull request {d} is not merged", .{number});
    const merge = pull.merge orelse return misuse(arena, "pull request {d} has no merge commit", .{number});
    const on = approve.parseDate(merged_on) orelse return misuse(arena, "pull request {d} gives no date of its merge", .{number});
    if (pull.approvers.len == 0) return .{ .text = try arena.print("skein: no one approved pull request {d} in review; nothing recorded\n", .{number}) };

    // both ends must be in the repository
    for ([_][]const u8{ pull.base, merge }) |commit| {
        if (try git.output(io, arena, ws.root, &.{ "cat-file", "-e", try arena.print("{s}^{{commit}}", .{commit}) }) != null) continue;
        _ = try git.remote(io, arena, ws.root, &.{ "fetch", "--quiet", "origin", commit }, 30);
    }
    var before = history.snapshot(io, arena, ws.root, pull.base) catch |e| return gone(arena, pull.base, e);
    defer before.deinit();
    var after = history.snapshot(io, arena, ws.root, merge) catch |e| return gone(arena, merge, e);
    defer after.deinit();
    const changed = try changes.compute(arena, .{ .graph = &before.graph, .schema = &before.project.schema }, .{ .graph = &after.graph, .schema = &after.project.schema });

    // the records must be readable, or writing them again would lose some
    const count = ws.report.problems.items.len;
    var approvals = try Approvals.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > count) return ws.problems();
    var files: std.ArrayList([]const u8) = .empty;
    var approved: usize = 0;
    for (changed) |c| {
        if (!(c.kind == .added or (c.kind == .changed and c.content))) continue;
        const item = after.graph.find(c.id) orelse continue;
        if (after.project.schema.itemType(item.type_name) == null) continue;
        for (pull.approvers) |by| try approvals.put(arena, &after.graph, &after.project.schema, item, by, on, null);
        const file = try Approvals.fileOf(arena, item);
        if (!Schema.names.contains(files.items, file)) try files.append(arena, file);
        approved += 1;
    }
    try approvals.write(io, arena, ws.root, &ws.graph, files.items);
    return .{ .text = try arena.print("skein: pull request {d}, merged {s}: {d} item{s} approved by {s}\n", .{ number, merged_on, approved, if (approved == 1) "" else "s", try std.mem.join(arena, ", ", pull.approvers) }) };
}

fn gone(arena: std.mem.Allocator, commit: []const u8, e: history.Error) !Workspace.Outcome {
    if (e == error.OutOfMemory) return error.OutOfMemory;
    return misuse(arena, "the commit {s} is not in this repository, and could not be fetched", .{commit[0..@min(commit.len, 12)]});
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
