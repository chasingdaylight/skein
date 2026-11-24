//! `skein overlay`: a what-if plan's deviations from what the forge holds
//! (forge/Overlay.zig). `skein overlay` lists them; `skein overlay ISSUE
//! FIELD VALUE` records one, with the value the forge says now as its
//! base; `--remove` takes one out. `skein apply` writes them to the forge.

const std = @import("std");
const Io = std.Io;

const Overlay = @import("../forge/Overlay.zig");
const Workspace = @import("Workspace.zig");
const checks = @import("../forge/checks.zig");
const cli = @import("../cli.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.OverlayCommand) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const before = ws.report.problems.items.len;
    var overlay = try Overlay.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();

    const target = options.issue orelse {
        if (overlay.entries.items.len == 0) return .{ .text = "The plan deviates from the forge nowhere.\n" };
        var out: std.ArrayList(u8) = .empty;
        for (overlay.entries.items) |e| try out.print(arena, "{s}  {t}: '{s}' -> '{s}'\n", .{ e.issue, e.field, e.base, e.value });
        return .{ .text = out.items };
    };
    const forge = ws.project.forge orelse return misuse(arena, "the project names no forge: add [forge] to {s}", .{@import("../Project.zig").config_file});
    const key = try Overlay.canonical(arena, &forge, target) orelse return misuse(arena, "'{s}' is no issue: write it #12 or owner/repo#12", .{target});
    const field_name = options.field orelse return misuse(arena, "say which field: assignees, milestone or state", .{});
    const field = std.meta.stringToEnum(Overlay.Field, field_name) orelse return misuse(arena, "'{s}' is no field of an issue skein writes: assignees, milestone or state", .{field_name});

    if (options.remove) {
        if (!overlay.remove(key, field)) return misuse(arena, "the overlay has no {t} of {s}", .{ field, key });
        try overlay.save(io, arena, ws.root);
        return .{ .text = try arena.print("skein: {s} {t} is the forge's again\n", .{ key, field }) };
    }
    const raw = options.value orelse return misuse(arena, "say the value: logins for assignees, a title (or - for none) for milestone, open or closed for state", .{});
    const value: []const u8 = switch (field) {
        .assignees => try Overlay.parseLogins(arena, if (std.mem.eql(u8, raw, "-")) "" else raw),
        .milestone => if (std.mem.eql(u8, raw, "-")) "" else raw,
        .state => if (std.mem.eql(u8, raw, "open") or std.mem.eql(u8, raw, "closed")) raw else return misuse(arena, "a state is open or closed", .{}),
    };
    // what the forge says now is what the deviation is based on
    const known = try checks.learnRefs(io, arena, ws.root, &ws.project, &.{key}, options.common.offline) orelse return misuse(arena, "the forge could not be asked", .{});
    const answer = try known.of(arena, key) orelse return misuse(arena, "the forge could not say anything of {s} ({s}): a deviation records what it is based on", .{ key, known.why });
    const issue = switch (answer) {
        .found => |i| i,
        else => return misuse(arena, "the forge has no issue {s}", .{key}),
    };
    const base = try Overlay.upstream(arena, issue, field);
    if (std.mem.eql(u8, base, value)) {
        _ = overlay.remove(key, field);
        try overlay.save(io, arena, ws.root);
        return .{ .text = try arena.print("skein: the forge says that already: {s} {t} is the forge's\n", .{ key, field }) };
    }
    try overlay.set(arena, key, field, base, value);
    try overlay.save(io, arena, ws.root);
    return .{ .text = try arena.print("skein: the plan changes {t} of {s} from '{s}' to '{s}', in {s}\n", .{ field, key, base, value, Overlay.file }) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
