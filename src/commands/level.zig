//! `skein level`: the moves that remove overallocation (planning/level.zig),
//! listed; with `--write`, written into the work items, for review like any
//! change on a branch. A fixed item gets its new start (and finish, when it
//! gives one); a float item that follows others waits longer after them
//! (`lag`); a float item that follows none gets a start, and the mode
//! `fixed` when it names `float`. `skein schedule` then gives the new plan.

const std = @import("std");
const Io = std.Io;

const Resources = @import("../planning/Resources.zig");
const Workspace = @import("Workspace.zig");
const attribute = @import("../edit/attribute.zig");
const cli = @import("../cli.zig");
const day = @import("../planning/day.zig");
const leveling = @import("../planning/level.zig");
const planning_forge = @import("../planning/forge.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Level) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const before = ws.report.problems.items.len;
    const resources = try Resources.of(io, arena, &ws, &ws.report) orelse
        return .{ .text = try arena.print("skein: releveling needs the people and what they can work: {s}\n", .{Resources.file}), .status = .misuse };
    if (ws.report.problems.items.len > before) return ws.problems();
    const works = (try planning_forge.collect(io, arena, ws.root, &ws.project, &ws.graph, options.common.offline)).works;
    const result = try leveling.level(arena, works, &resources);

    var out: std.ArrayList(u8) = .empty;
    if (result.moves.len == 0 and result.stuck.len == 0) return .{ .text = "skein: nobody has more work than time; nothing to move\n" };
    var written: usize = 0;
    var by_hand: std.ArrayList([]const u8) = .empty;
    for (result.moves) |m| {
        const e = m.entry;
        try out.print(arena, "{s}: {s} to {s}, from {s}", .{ e.work.id, &day.format(m.start), &day.format(m.finish), &day.format(e.start.?) });
        const what = try change(arena, m);
        if (what.len == 0) {
            try out.appendSlice(arena, " (its predecessors move it)\n");
            continue;
        }
        try out.print(arena, " ({s})\n", .{try describe(arena, what)});
        if (!options.write) continue;
        if (try writeChange(io, arena, &ws, m, what)) written += 1 else try by_hand.append(arena, e.work.id);
    }
    for (result.stuck) |w| try out.print(arena, "{s}: no room for it within two years; left where it is\n", .{w.id});
    if (options.write) {
        try out.print(arena, "skein: wrote the moves into {d} work item{s}; run skein schedule for the plan\n", .{ written, if (written == 1) "" else "s" });
        if (by_hand.items.len > 0) try out.print(arena, "skein: write the moves by hand into {s}\n", .{try std.mem.join(arena, ", ", by_hand.items)});
    } else try out.appendSlice(arena, "skein: nothing written; --write writes these moves into the work items\n");
    return .{ .text = out.items };
}

/// What the move writes, role by role
const Change = struct { role: Role, value: []const u8 };
const Role = enum { start, finish, lag, mode };

fn change(arena: std.mem.Allocator, m: leveling.Move) ![]const Change {
    const e = m.entry;
    const w = e.work;
    var out: std.ArrayList(Change) = .empty;
    if (e.mode == .float and w.after.len > 0) {
        if (m.extra_lag > 0) try out.append(arena, .{ .role = .lag, .value = try arena.print("{d}", .{w.lag + m.extra_lag}) });
        return out.items;
    }
    try out.append(arena, .{ .role = .start, .value = try arena.dupe(u8, &day.format(m.start)) });
    if (e.mode == .fixed and w.finish != null) try out.append(arena, .{ .role = .finish, .value = try arena.dupe(u8, &day.format(m.finish)) });
    if (e.mode == .float) if (w.written_mode != null) try out.append(arena, .{ .role = .mode, .value = "fixed" });
    return out.items;
}

fn describe(arena: std.mem.Allocator, what: []const Change) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    for (what) |c| try parts.append(arena, try arena.print("{t} = {s}", .{ c.role, c.value }));
    return std.mem.join(arena, ", ", parts.items);
}

/// Writes the change into the item; false when it is to be done by hand
fn writeChange(io: Io, arena: std.mem.Allocator, ws: *Workspace, m: leveling.Move, what: []const Change) !bool {
    const w = m.entry.work;
    // another repository's work, and a read-only source, are not written here
    if (w.repo != null) return false;
    const item = w.item;
    if (ws.project.readOnlySource(item.file) != null) return false;
    const t = ws.project.schema.itemType(item.type_name) orelse return false;
    const planning = t.planning orelse return false;
    var text: []const u8 = try ws.root.readFileAlloc(io, item.file, arena, .limited(1 << 26));
    for (what) |c| {
        const key = planning.attribute(switch (c.role) {
            .start => .start,
            .finish => .finish,
            .lag => .lag,
            .mode => .mode,
        }) orelse return false;
        // in front matter, a date and a number are bare, a mode a string
        const toml_value = if (c.role == .mode) try arena.print("\"{s}\"", .{c.value}) else c.value;
        text = (if (item.in_document) try attribute.marker(arena, text, item.line, key, c.value) else try attribute.frontMatter(arena, text, key, toml_value)) orelse return false;
    }
    try ws.root.writeFile(io, .{ .sub_path = item.file, .data = text });
    return true;
}

test {
    _ = @import("_test/level.zig");
}
