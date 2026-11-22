//! `skein apply`: writes the overlay's deviations to the forge, through the
//! adapter, and takes the ones that were written out of the overlay. A
//! deviation whose upstream value has changed since it was made is not
//! written (the field changed on both sides: for a decision) unless
//! `--force`. `--dry-run` says what would be written.

const std = @import("std");
const Io = std.Io;

const Overlay = @import("../forge/Overlay.zig");
const Workspace = @import("Workspace.zig");
const checks = @import("../forge/checks.zig");
const cli = @import("../cli.zig");
const github = @import("../forge/github.zig");
const history = @import("../history.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Apply) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const before = ws.report.problems.items.len;
    var overlay = try Overlay.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const forge = ws.project.forge orelse return misuse(arena, "the project names no forge: nothing to write to", .{});
    if (overlay.entries.items.len == 0) return .{ .text = "The plan deviates from the forge nowhere: nothing to write.\n" };
    if (options.common.offline) return misuse(arena, "writing to the forge needs it: not with --offline", .{});
    const git_dir = history.gitDir(io, arena, ws.root) catch return misuse(arena, "this is no git repository", .{});
    const body_path = try Io.Dir.path.join(arena, &.{ git_dir, "skein", "forge", "update.json" });

    // the issues, in order of first mention
    var issues: std.ArrayList([]const u8) = .empty;
    for (overlay.entries.items) |e| {
        const seen = for (issues.items) |i| {
            if (std.mem.eql(u8, i, e.issue)) break true;
        } else false;
        if (!seen) try issues.append(arena, e.issue);
    }
    var out: std.ArrayList(u8) = .empty;
    var written: usize = 0;
    var left: usize = 0;
    for (issues.items) |key| {
        const r = forge.ref(key).?;
        const answer = checks.lookup(io, arena, &forge, r) catch |e| github.Answer{ .unreachable_ = try arena.print("{t}", .{e}) };
        const issue = switch (answer) {
            .found => |i| i,
            .missing => {
                try out.print(arena, "{s}: the forge has no such issue; left in the overlay\n", .{key});
                left += 1;
                continue;
            },
            .unreachable_ => |why| {
                try out.print(arena, "{s}: the forge could not be asked ({s}); left in the overlay\n", .{ key, why });
                left += 1;
                continue;
            },
        };
        var changes: github.Changes = .{};
        var done: std.ArrayList(Overlay.Field) = .empty;
        for (overlay.entries.items) |e| {
            if (!std.mem.eql(u8, e.issue, key)) continue;
            const now = try Overlay.upstream(arena, issue, e.field);
            if (std.mem.eql(u8, now, e.value)) {
                // the forge says it already
                try done.append(arena, e.field);
                continue;
            }
            if (!std.mem.eql(u8, now, e.base) and !options.force) {
                try out.print(arena, "{s} {t}: changed on both sides (the plan from '{s}' to '{s}', the forge to '{s}'); not written, left in the overlay; --force writes the plan's\n", .{ key, e.field, e.base, e.value, now });
                left += 1;
                continue;
            }
            switch (e.field) {
                .assignees => changes.assignees = if (e.value.len == 0) &.{} else try split(arena, e.value),
                .milestone => changes.milestone = e.value,
                .state => changes.state = e.value,
            }
            try done.append(arena, e.field);
            try out.print(arena, "{s} {t}: '{s}' -> '{s}'{s}\n", .{ key, e.field, now, e.value, if (options.dry_run) " (dry run)" else "" });
        }
        const something = changes.assignees != null or changes.milestone != null or changes.state != null;
        if (something and !options.dry_run) {
            if (try checks.update(io, arena, &forge, r, changes, body_path)) |why| {
                try out.print(arena, "{s}: not written: {s}; left in the overlay\n", .{ key, why });
                left += done.items.len;
                continue;
            }
        }
        if (!options.dry_run) for (done.items) |f| {
            _ = overlay.remove(key, f);
            written += 1;
        };
    }
    if (!options.dry_run) try overlay.save(io, arena, ws.root);
    try out.print(arena, "skein: {d} deviation{s} {s} the forge, {d} left in the overlay\n", .{ written, if (written == 1) "" else "s", if (options.dry_run) "would be written to" else "written to", left });
    return .{ .text = out.items, .status = if (left > 0) .problems else .ok };
}

fn split(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, text, ',');
    while (it.next()) |w| try list.append(arena, w);
    return list.items;
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
